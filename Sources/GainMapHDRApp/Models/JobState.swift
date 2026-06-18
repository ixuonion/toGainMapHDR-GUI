import Foundation

enum JobStatus: Equatable {
    case queued
    case running
    case finished
    case failed(String)
    case cancelled

    var title: String {
        switch self {
        case .queued: L10n.text("queued")
        case .running: L10n.text("running")
        case .finished: L10n.text("finished")
        case .failed: L10n.text("failed")
        case .cancelled: L10n.text("cancelled")
        }
    }
}

struct ConversionJob: Identifiable, Equatable {
    let id = UUID()
    let input: ImageInput
    var status: JobStatus = .queued
    var log: String = ""
}
