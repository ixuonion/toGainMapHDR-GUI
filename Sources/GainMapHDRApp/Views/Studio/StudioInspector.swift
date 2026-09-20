import SwiftUI

struct StudioInspector: View {
    @Bindable var store: ConversionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("demo_inspector")).font(.headline)
                Text(L10n.text("demo_batch_note")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: StudioLayout.headerHeight, alignment: .leading)
            Divider()
            Form {
                StudioOutputSettings(store: store, outputURL: store.outputURL)
                StudioEncodingSettings(settings: $store.settings)
                StudioAdvancedSettings(settings: $store.settings)
            }
            .formStyle(.grouped)
            .disabled(store.isConverting || store.isImporting)
            Divider()
            HStack {
                Text("HEIC")
                Spacer()
                Text(store.settings.outputMode.title).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: StudioLayout.footerHeight)
        }
    }
}

private struct StudioOutputSettings: View {
    @Bindable var store: ConversionStore
    let outputURL: URL?
    var body: some View {
        Section(L10n.text("output")) {
            LabeledContent(L10n.text("format"), value: "HEIC")
            Picker(L10n.text("destination"), selection: $store.settings.destinationChoice) {
                ForEach(DestinationChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            if store.settings.destinationChoice == .custom {
                Button(L10n.text("choose_folder"), systemImage: "folder") { store.pickOutputFolder() }
            }
            Text(store.settings.destinationChoice == .photosLibrary
                 ? L10n.text("photos_destination_note")
                 : outputURL?.path(percentEncoded: false) ?? L10n.text("choose_output_destination"))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(store.settings.destinationChoice == .photosLibrary ? nil : 2).truncationMode(.middle).textSelection(.enabled)
            if store.settings.destinationChoice == .sourceFolder {
                Text(L10n.text("demo_destination_note"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(L10n.text("naming"), selection: $store.settings.namingPolicy) {
                ForEach(NamingPolicy.allCases) { policy in Text(policy.title).tag(policy) }
            }
        }
    }
}

private struct StudioEncodingSettings: View {
    @Binding var settings: ConversionSettings
    var body: some View {
        Section(L10n.text("encoding")) {
            Picker(L10n.text("output_mode"), selection: $settings.outputMode) {
                ForEach(OutputMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Picker(L10n.text("color_space"), selection: $settings.colorSpace) {
                ForEach(ColorSpaceOption.allCases) { space in Text(space.title).tag(space) }
            }
            Picker(L10n.text("bit_depth"), selection: $settings.displayBitDepth) {
                ForEach(BitDepthOption.allCases) { depth in Text(depth.title).tag(depth) }
            }
            .disabled(settings.outputMode == .pqHDR)
            StudioSlider(title: L10n.text("quality"), value: $settings.qualityValue, precision: 0)
        }
    }
}

private struct StudioAdvancedSettings: View {
    @Binding var settings: ConversionSettings
    @State private var expanded = false
    var body: some View {
        Section {
            if expanded {
                StudioSlider(title: L10n.text("tone_ratio"), value: $settings.toneMappingRatio, precision: 1)
                    .disabled(settings.outputMode == .pqHDR || settings.outputMode == .hlgHDR)
                StudioSlider(title: L10n.text("max_headroom"), value: $settings.maxHeadroom, precision: 1)
                Toggle(L10n.text("half_size"), isOn: $settings.subsampleGainMap)
                Toggle(L10n.text("monochrome"), isOn: $settings.displayMonochrome)
                    .disabled(settings.outputMode != .isoGainMap)
                Picker(L10n.text("concurrency"), selection: $settings.concurrency) {
                    Text(L10n.text("auto_concurrency")).tag(0)
                    ForEach([1, 2, 4, 8], id: \.self) { count in Text(count, format: .number).tag(count) }
                }
            }
        } header: {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .frame(width: 10)
                    Text(L10n.text("advanced"))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.text(expanded ? "hide_details" : "show_details"))
        }
    }
}

private struct StudioSlider: View {
    let title: String
    @Binding var value: Double
    let precision: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number.precision(.fractionLength(precision)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .onChange(of: value) { _, newValue in
                        value = newValue.isFinite ? min(100, max(1, newValue)) : 1
                    }
            }
            Slider(value: $value, in: 1...100)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}
