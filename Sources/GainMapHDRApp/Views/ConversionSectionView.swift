import SwiftUI

struct ConversionSectionView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        GlassSection(title: L10n.text("convert_section"), systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProgressView(value: store.progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(store.progress * 100))%")
                        .font(AppTypography.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                if store.jobs.isEmpty {
                    Text(L10n.text("queue_empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(store.jobs) { job in
                            HStack {
                                Text(job.input.displayName)
                                    .font(AppTypography.body)
                                    .lineLimit(1)
                                Spacer()
                                StatusBadge(status: job.status)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
