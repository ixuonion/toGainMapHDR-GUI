import SwiftUI

struct InputSidebarView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("gainmaphdr"))
                    .font(AppTypography.largeTitle)
                Label(store.modeTitle, systemImage: store.inputs.count > 1 ? "rectangle.stack" : "photo")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if store.inputs.isEmpty {
                emptyState
            } else {
                inputList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .regular))
                .symbolEffect(.pulse, options: .repeat(.periodic(delay: 1.8)))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(L10n.text("add_hdr_images"))
                    .font(AppTypography.sectionTitle)
                Text(L10n.text("supported_formats"))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button(L10n.text("add_images")) { store.pickInputImages() }
                    .help(L10n.text("add_images"))
                Button(L10n.text("add_folder")) { store.pickInputFolder() }
                    .help(L10n.text("add_folder"))
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var inputList: some View {
        List(selection: $store.selectedInputID) {
            if store.inputs.count > 5 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(store.collectionSummaryTitle, systemImage: "rectangle.stack.fill")
                                .font(AppTypography.sectionTitle)
                            Spacer()
                            Button {
                                store.clearInputs()
                            } label: {
                                Label(L10n.text("clear_all"), systemImage: "xmark.circle")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help(L10n.text("clear_all"))
                            .disabled(store.isConverting)

                            Button(store.isCollectionExpanded ? L10n.text("hide_details") : L10n.text("show_details")) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    store.isCollectionExpanded.toggle()
                                }
                            }
                            .buttonStyle(.link)
                        }

                        Text(L10n.text("details_below"))
                            .font(AppTypography.auxiliary)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if store.inputs.count <= 5 || store.isCollectionExpanded {
                Section(L10n.text("input")) {
                    ForEach(store.inputs) { input in
                        InputRow(input: input)
                            .tag(input.id)
                            .contextMenu {
                                Button(L10n.text("remove")) {
                                    store.removeInput(id: input.id)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct InputRow: View {
    let input: ImageInput

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(input.displayName)
                    .font(AppTypography.body)
                    .lineLimit(1)
                Text(input.directoryName)
                    .font(AppTypography.auxiliary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "photo")
        }
    }
}
