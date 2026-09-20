import SwiftUI

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Label(status.title, systemImage: symbolName)
            .font(AppTypography.body)
            .foregroundStyle(foregroundStyle)
    }

    private var symbolName: String {
        switch status {
        case .queued: "clock"
        case .running, .savingPhotos, .authorizingPhotos: "progress.indicator"
        case .finished, .savedToPhotos: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        switch status {
        case .finished, .savedToPhotos:
            AnyShapeStyle(.green)
        case .failed:
            AnyShapeStyle(.red)
        case .cancelled:
            AnyShapeStyle(.secondary)
        case .queued, .running, .savingPhotos, .authorizingPhotos:
            AnyShapeStyle(.secondary)
        }
    }
}
