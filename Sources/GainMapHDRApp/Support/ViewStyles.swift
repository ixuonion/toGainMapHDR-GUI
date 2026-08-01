import SwiftUI

struct GlassSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(AppTypography.sectionTitle)

            content
                .font(AppTypography.body)
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(sectionStroke, lineWidth: 1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(AppTypography.subsectionTitle)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            }
            .padding(.bottom, 14)

            Divider()
                .padding(.bottom, 14)
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let labelWidth: CGFloat
    let controlWidth: CGFloat
    @ViewBuilder var content: Content

    init(
        _ title: String,
        labelWidth: CGFloat = 140,
        controlWidth: CGFloat = 340,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelWidth = labelWidth
        self.controlWidth = controlWidth
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                rowLabel
                    .frame(width: labelWidth, alignment: .leading)

                Spacer(minLength: 16)

                content
                    .frame(maxWidth: min(controlWidth, 520), alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                rowLabel
                content
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowLabel: some View {
        Text(title)
            .font(AppTypography.body)
            .foregroundStyle(.primary)
    }
}

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
        case .running: "progress.indicator"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        switch status {
        case .finished:
            AnyShapeStyle(.green)
        case .failed:
            AnyShapeStyle(.red)
        case .cancelled:
            AnyShapeStyle(.secondary)
        case .queued, .running:
            AnyShapeStyle(.secondary)
        }
    }
}
