import SwiftUI

struct OutputSectionView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        GlassSection(title: L10n.text("output"), systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(L10n.text("destination"), controlWidth: 300) {
                    HStack(spacing: 6) {
                        Button {
                            store.pickOutputFolder()
                        } label: {
                            Label(L10n.text("choose"), systemImage: "folder")
                        }
                        .help(L10n.text("choose_folder"))
                    }
                    .frame(width: 300, alignment: .trailing)
                }

                SettingsRow(L10n.text("naming"), controlWidth: 300) {
                    Picker(L10n.text("naming"), selection: $store.settings.namingPolicy) {
                        ForEach(NamingPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300, alignment: .trailing)
                }

                SettingsRow(L10n.text("format"), controlWidth: 300) {
                    Picker(L10n.text("format"), selection: $store.settings.format) {
                        ForEach(OutputFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300, alignment: .trailing)
                }
            }
        }
    }
}
