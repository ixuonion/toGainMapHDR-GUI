import Foundation

struct ConversionUpdate: Sendable {
    var statuses: [UUID: JobStatus]
    var log: String?
    var finished: Bool
}

/// Producers never enter MainActor. The store drains at most ten times per second.
actor ConversionEventBuffer {
    private var statuses: [UUID: JobStatus] = [:]
    private var lines: [String] = []
    private var bytes = 0
    private var logChanged = false
    private var finished = false
    private let names: [UUID: String]

    init(inputs: [ImageInput] = []) {
        names = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0.displayName) })
    }

    func append(_ text: String, inputID: UUID? = nil) {
        guard !text.isEmpty else { return }
        let prefix = inputID.flatMap { names[$0] }.map { "[\($0)] " } ?? ""
        let line = prefix + String(text.prefix(4096))
        lines.append(line)
        bytes += line.utf8.count
        while lines.count > 200 || bytes > 64 * 1024 {
            bytes -= lines.removeFirst().utf8.count
        }
        logChanged = true
    }

    func set(_ status: JobStatus, for id: UUID) { statuses[id] = status }
    func finish() { finished = true }

    func drain() -> ConversionUpdate {
        let update = ConversionUpdate(statuses: statuses, log: logChanged ? lines.joined(separator: "\n") : nil, finished: finished)
        statuses.removeAll(keepingCapacity: true)
        logChanged = false
        return update
    }
}
