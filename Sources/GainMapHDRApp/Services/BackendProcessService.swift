import Foundation

enum ConversionServiceError: LocalizedError {
    case failed(Int32)

    var errorDescription: String? {
        switch self {
        case .failed(let code):
            "Backend conversion failed with exit code \(code)."
        }
    }
}

protocol BackendConverting: Sendable {
    func run(command: ConversionCommand, progress: @escaping @Sendable (String) -> Void) async throws
    func cancel()
}

final class BackendProcessService: BackendConverting, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []

    func run(command: ConversionCommand, progress: @escaping @Sendable (String) -> Void) async throws {
        var resolvedCommand = command
        if !command.executable.contains("/") {
            resolvedCommand.arguments = [command.executable] + command.arguments
            resolvedCommand.executable = "/usr/bin/env"
        }

        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedCommand.executable)
            process.arguments = resolvedCommand.arguments
            process.environment = environment()
            process.currentDirectoryURL = BundledBackend.workingDirectory(for: command.executable)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                progress(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            process.terminationHandler = { [weak self] process in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.remove(process)
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ConversionServiceError.failed(process.terminationStatus))
                }
            }

            do {
                append(process)
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                remove(process)
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        lock.lock()
        let activeProcesses = processes
        lock.unlock()

        for process in activeProcesses {
            process.terminate()
        }
    }

    private func append(_ process: Process) {
        lock.lock()
        processes.append(process)
        lock.unlock()
    }

    private func remove(_ process: Process) {
        lock.lock()
        processes.removeAll { $0 === process }
        lock.unlock()
    }

    private func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(defaultPath):\(path)"
        } else {
            environment["PATH"] = defaultPath
        }
        return environment
    }
}
