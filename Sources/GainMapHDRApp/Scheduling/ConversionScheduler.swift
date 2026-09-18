import Foundation
import ImageIO

struct WorkerPolicy: Sendable {
    /// The measured search ceiling is eight; source size and a half-RAM budget cap Auto.
    /// On the validation M5 Max (36 GiB), 32-bit 32.7 MP TIFFs select six workers.
    static func count(requested: Int, inputCount: Int, largestPixelCount: Int = 0,
                      physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Int {
        let memoryPerWorker = max(UInt64(2 * 1024 * 1024 * 1024), UInt64(max(0, largestPixelCount)) * 96)
        let memoryCap = max(1, Int((physicalMemory / 2) / memoryPerWorker))
        let requestedCap = requested == 0 ? 8 : min(8, max(1, requested))
        return max(1, min(inputCount, requestedCap, memoryCap))
    }
}

actor ConversionScheduler {
    private let backend: any BackendConverting
    init(backend: any BackendConverting = BackendProcessService()) { self.backend = backend }

    func run(_ request: ConversionRequest, events: ConversionEventBuffer) async {
        let fileAccess = FileAccessService()
        var largestPixels = 0
        var reserved = Set<String>()
        var pending: [ImageInput] = []
        var examined = Set<UUID>()
        for input in request.inputs {
            if Task.isCancelled { break }
            examined.insert(input.id)
            do {
                guard let destination = request.outputFile(for: input) else {
                    throw ConversionFailure(kind: .output, detail: L10n.text("choose_output_destination"))
                }
                // Resolve aliases and case differences conservatively before parallel writes.
                let key = destination.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
                guard reserved.insert(key).inserted else {
                    throw ConversionFailure(kind: .output, detail: L10n.text("output_collision") + " " + destination.lastPathComponent)
                }
                largestPixels = max(largestPixels, try await fileAccess.validate(input: input.url, destination: destination))
                pending.append(input)
            } catch {
                await events.set(.failed(error.localizedDescription), for: input.id)
                await events.append(error.localizedDescription, inputID: input.id)
            }
        }
        for input in request.inputs where !examined.contains(input.id) {
            await events.set(.cancelled, for: input.id)
        }
        let count = WorkerPolicy.count(requested: request.settings.concurrency, inputCount: pending.count, largestPixelCount: largestPixels)
        await events.append(String(format: L10n.text("worker_count"), count))
        let backend = self.backend
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func submit(_ input: ImageInput) {
                group.addTask {
                    guard !Task.isCancelled else { await events.set(.cancelled, for: input.id); return }
                    await events.set(.running, for: input.id)
                    do {
                        try await Self.convert(input, request: request, backend: backend, events: events)
                        await events.set(.finished, for: input.id)
                        await events.append(L10n.text("finished"), inputID: input.id)
                    } catch {
                        let status: JobStatus = Task.isCancelled || error is CancellationError ? .cancelled : .failed(error.localizedDescription)
                        await events.set(status, for: input.id)
                        await events.append(status == .cancelled ? L10n.text("cancelled") : error.localizedDescription, inputID: input.id)
                    }
                }
            }
            while next < min(count, pending.count), !Task.isCancelled {
                submit(pending[next]); next += 1
            }
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll() }
                else if next < pending.count { submit(pending[next]); next += 1 }
            }
            for input in pending.dropFirst(next) { await events.set(.cancelled, for: input.id) }
        }
        await events.finish()
    }

    private static func convert(_ input: ImageInput, request: ConversionRequest,
                                backend: any BackendConverting, events: ConversionEventBuffer) async throws {
        try Task.checkCancellation()
        guard var command = request.command(for: input), let target = request.outputFile(for: input) else {
            throw ConversionFailure(kind: .output, detail: L10n.text("choose_output_destination"))
        }
        let access = [input.url, target.deletingLastPathComponent()].filter { $0.startAccessingSecurityScopedResource() }
        defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let staging = target.deletingLastPathComponent().appendingPathComponent(".GainMapHDR-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: false) }
        catch { throw ConversionFailure(kind: .permission, detail: error.localizedDescription) }
        defer { try? fm.removeItem(at: staging) }
        // Only the output directory changes: the reference binary and all image options stay intact.
        command.arguments[1] = staging.path
        try await backend.run(command: command, log: events, inputID: input.id)
        try Task.checkCancellation()
        let result = staging.appendingPathComponent(target.lastPathComponent)
        guard let source = CGImageSourceCreateWithURL(result as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) as String? == "public.heic",
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw ConversionFailure(kind: .output, detail: L10n.text("invalid_output"))
        }
        try Task.checkCancellation()
        do {
            // Never replace existing output, including a target created after preflight.
            try OutputPublisher.publish(result, to: target)
        } catch { throw ConversionFailure(kind: .output, detail: error.localizedDescription) }
    }
}
