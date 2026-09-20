import Foundation

enum JobStatus: Equatable, Sendable {
    case queued
    case running
    case authorizingPhotos
    case savingPhotos
    case savedToPhotos
    case finished
    case failed(String)
    case cancelled

    var isPending: Bool {
        switch self {
        case .queued, .running, .authorizingPhotos, .savingPhotos: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .queued: L10n.text("queued")
        case .running: L10n.text("running")
        case .authorizingPhotos: L10n.text("photos_authorizing")
        case .savingPhotos: L10n.text("photos_saving")
        case .savedToPhotos: L10n.text("photos_saved")
        case .finished: L10n.text("finished")
        case .failed: L10n.text("failed")
        case .cancelled: L10n.text("cancelled")
        }
    }
}

struct ConversionJob: Identifiable, Equatable, Sendable {
    let id = UUID()
    let input: ImageInput
    var status: JobStatus = .queued
    var log: String = ""
}
