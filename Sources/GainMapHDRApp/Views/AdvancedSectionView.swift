import SwiftUI

struct AdvancedSectionView: View {
    @Bindable var store: ConversionStore

    var body: some View {
        GlassSection(title: L10n.text("advanced"), systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                encodingGroup
                toneMappingGroup
                performanceGroup
                commandGroup
            }
        }
    }

    private var encodingGroup: some View {
        SettingsGroup(title: L10n.text("encoding"), systemImage: "photo.badge.checkmark") {
            SettingsRow(L10n.text("output_mode")) {
                Picker(L10n.text("output_mode"), selection: $store.settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 260, alignment: .trailing)
            }

            SettingsRow(L10n.text("color_space")) {
                Picker(L10n.text("color_space"), selection: $store.settings.colorSpace) {
                    ForEach(ColorSpaceOption.allCases) { colorSpace in
                        Text(colorSpace.title).tag(colorSpace)
                    }
                }
                .labelsHidden()
                .frame(width: 260, alignment: .trailing)
            }

            SettingsRow(L10n.text("bit_depth")) {
                Picker("", selection: $store.settings.bitDepth) {
                    ForEach(BitDepthOption.allCases) { bitDepth in
                        Text(bitDepth.title).tag(bitDepth)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180, alignment: .trailing)
            }

            SettingsRow(L10n.text("gain_map")) {
                HStack(spacing: 18) {
                    Toggle(L10n.text("half_size"), isOn: $store.settings.subsampleGainMap)
                    Toggle(L10n.text("monochrome"), isOn: $store.settings.monochromeGainMap)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var toneMappingGroup: some View {
        SettingsGroup(title: L10n.text("tone_mapping"), systemImage: "sun.max") {
            numericSliderRow(
                title: L10n.text("quality"),
                value: Binding(
                    get: { Double(store.settings.quality) },
                    set: { store.settings.quality = Int($0.rounded()) }
                ),
                range: 1...100,
                text: Binding(
                    get: { Double(store.settings.quality) },
                    set: { store.settings.quality = Int($0.rounded()) }
                ),
                precision: 0
            )

            numericSliderRow(
                title: L10n.text("tone_ratio"),
                value: $store.settings.toneMappingRatio,
                range: 1...100,
                text: $store.settings.toneMappingRatio,
                precision: 1
            )

            numericSliderRow(
                title: L10n.text("max_headroom"),
                value: $store.settings.maxHeadroom,
                range: 1...100,
                text: $store.settings.maxHeadroom,
                precision: 1
            )
        }
    }

    private var performanceGroup: some View {
        SettingsGroup(title: L10n.text("performance"), systemImage: "cpu") {
            SettingsRow(L10n.text("concurrency")) {
                Stepper(value: $store.settings.concurrency, in: 1...max(ProcessInfo.processInfo.processorCount, 1)) {
                    Text("\(store.settings.concurrency) \(store.settings.concurrency == 1 ? L10n.text("worker") : L10n.text("workers"))")
                        .font(AppTypography.body)
                        .monospacedDigit()
                }
                .frame(width: 180, alignment: .trailing)
            }
        }
    }

    private var commandGroup: some View {
        SettingsGroup(title: L10n.text("command"), systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(L10n.text("backend_command"), controlWidth: 620) {
                    CommandDisplayView(command: store.representativeConversionCommand)
                }

                SettingsRow(L10n.text("log"), controlWidth: 620) {
                    ScrollView {
                        Text(store.logText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 120)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func numericSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: Binding<Double>,
        precision: Int
    ) -> some View {
        SettingsRow(title) {
            HStack(spacing: 10) {
                Text("\(Int(range.lowerBound))")
                    .font(AppTypography.auxiliary)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .leading)

                Slider(value: value, in: range)
                    .frame(width: 180)

                Text("\(Int(range.upperBound))")
                    .font(AppTypography.auxiliary)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, alignment: .trailing)

                TextField(title, value: text, format: .number.precision(.fractionLength(precision)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
