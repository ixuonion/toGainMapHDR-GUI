import SwiftUI

struct DetailView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                OutputSectionView(store: store)
                ConversionSectionView(store: store)
                AdvancedSectionView(store: store)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 960, alignment: .leading)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color(nsColor: .controlBackgroundColor).opacity(0.34)
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text(L10n.text("details"))
                .font(AppTypography.largeTitle)

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(store.modeTitle)
                    .font(AppTypography.sectionTitle)
                Text(store.outputURL?.path(percentEncoded: false) ?? L10n.text("choose_output_destination"))
                    .font(AppTypography.auxiliary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 220, alignment: .trailing)
        }
    }
}
