import Foundation
import Subprocess

struct ConversionFailure: LocalizedError, Sendable, Equatable {
    enum Kind: String, Sendable { case input, backendMissing, permission, output, unsupported, process }
    let kind: Kind
    let detail: String
    var errorDescription: String? { "\(L10n.text("error_" + kind.rawValue)): \(detail)" }
}

protocol BackendConverting: Sendable {
    func run(command: ConversionCommand, log: ConversionEventBuffer, inputID: UUID) async throws
}

/// Each invocation owns its process and pipes. No process registry or UI callbacks.
struct BackendProcessService: BackendConverting {
    func run(command: ConversionCommand, log: ConversionEventBuffer, inputID: UUID) async throws {
        try Task.checkCancellation()
        let executable = command.executable == "toGainMapHDR" ? BundledBackend.executablePath : command.executable
        guard FileManager.default.fileExists(atPath: executable) else {
            throw ConversionFailure(kind: .backendMissing, detail: executable)
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ConversionFailure(kind: .permission, detail: executable)
        }
        var options = PlatformOptions()
        options.qualityOfService = .userInitiated
        options.createSession = true
        options.teardownSequence = [.send(signal: .terminate, toProcessGroup: true, allowedDurationToNextStep: .seconds(1))]
        do {
            let result = try await Subprocess.run(
                .path(.init(executable)), arguments: Arguments(command.arguments),
                workingDirectory: BundledBackend.workingDirectory(for: executable).map { .init($0.path) },
                platformOptions: options, input: .none, output: .sequence, error: .combinedWithOutput
            ) { execution in
                var tail = ""
                for try await line in execution.standardOutput.strings(bufferingPolicy: .maxLineLength(128 * 1024)) {
                    try Task.checkCancellation()
                    // Both the per-process diagnostic tail and the shared log have hard limits.
                    tail = String((tail + "\n" + line).suffix(8192))
                    await log.append(line, inputID: inputID)
                }
                return tail
            }
            try Task.checkCancellation()
            guard result.terminationStatus.isSuccess else {
                let detail = result.closureResult.isEmpty ? String(describing: result.terminationStatus) : result.closureResult
                let kind: ConversionFailure.Kind
                if result.terminationStatus == .exited(22) { kind = .unsupported }
                else if detail.localizedCaseInsensitiveContains("permission") { kind = .permission }
                else { kind = .process }
                throw ConversionFailure(kind: kind, detail: detail)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let failure = error as? ConversionFailure { throw failure }
            throw ConversionFailure(kind: .process, detail: error.localizedDescription)
        }
    }
}
