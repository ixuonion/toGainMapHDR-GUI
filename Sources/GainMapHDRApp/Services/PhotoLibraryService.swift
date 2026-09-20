import Foundation
import Photos

/// Implementations must await the final import result even if cancelled after submission.
/// The caller owns the file and keeps it alive until this method returns.
protocol PhotoLibrarySaving: Sendable {
    func authorize() async throws
    func save(file: URL, originalFilename: String) async throws
}

protocol PhotoLibraryAuthorizing: Sendable {
    func status() -> PHAuthorizationStatus
    func request() async throws -> PHAuthorizationStatus
}

struct SystemPhotoAuthorization: PhotoLibraryAuthorizing {
    func status() -> PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .addOnly) }

    func request() async throws -> PHAuthorizationStatus {
        // Running the bare SwiftPM executable does not supply the application's privacy plist.
        guard let description = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String,
              !description.isEmpty else { throw PhotoLibraryFailure.missingUsageDescription }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}

struct PhotoLibraryService: PhotoLibrarySaving {
    let authorization: any PhotoLibraryAuthorizing

    init(authorization: any PhotoLibraryAuthorizing = SystemPhotoAuthorization()) {
        self.authorization = authorization
    }

    func authorize() async throws {
        try Task.checkCancellation()
        var status = authorization.status()
        if status == .notDetermined {
            status = try await authorization.request()
        }
        try Task.checkCancellation()
        switch status {
        case .authorized: return
        case .restricted: throw PhotoLibraryFailure.restricted
        default: throw PhotoLibraryFailure.denied
        }
    }

    func save(file: URL, originalFilename: String) async throws {
        try Task.checkCancellation()
        // No cancellation handler: PhotoKit transactions cannot be rolled back by Task cancellation.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                options.shouldMoveFile = false
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: options)
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: PhotoLibraryFailure.importFailed(error?.localizedDescription)) }
            }
        }
    }
}

enum PhotoLibraryFailure: Error, LocalizedError {
    case missingUsageDescription
    case denied
    case restricted
    case importFailed(String?)

    var errorDescription: String? {
        switch self {
        case .missingUsageDescription: L10n.text("photos_missing_usage")
        case .denied: L10n.text("photos_denied")
        case .restricted: L10n.text("photos_restricted")
        case .importFailed(let detail): L10n.text("photos_save_failed") + (detail.map { " " + $0 } ?? "")
        }
    }
}
