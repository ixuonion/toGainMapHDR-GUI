import SwiftUI

/// Decoration never changes the determinate progress or its accessibility value.
struct ConversionProgressBar: View {
    let value: Double
    let isRunning: Bool

    var body: some View {
        ProgressView(value: min(1, max(0, value.isFinite ? value : 0)))
            .progressViewStyle(SpectralProgressStyle(isRunning: isRunning))
            .accessibilityLabel(L10n.text("convert_section"))
    }
}

private struct SpectralProgressStyle: ProgressViewStyle {
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        let animates = isRunning && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
            let phase = animates ? (sin(context.date.timeIntervalSinceReferenceDate * .pi / 2) + 1) / 2 : 0.5
            GeometryReader { geometry in
                let colors: [Color] = contrast == .increased
                    ? [.accentColor, .accentColor]
                    : [.blue, .cyan, .indigo, .blue]
                let spectrum = LinearGradient(colors: colors,
                    startPoint: UnitPoint(x: phase * 2 - 1, y: 0),
                    endPoint: UnitPoint(x: phase * 2 + 0.5, y: 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    // A fine luminous edge signals work even before the first file finishes.
                    Capsule().strokeBorder(spectrum.opacity(isRunning ? 0.7 : 0), lineWidth: 1)
                    Capsule()
                        .fill(isRunning ? AnyShapeStyle(spectrum) : AnyShapeStyle(Color.accentColor))
                        .frame(width: geometry.size.width * fraction)
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(contrast == .increased ? 0 : 0.28))
                                .frame(height: 1).padding(.horizontal, 3)
                        }
                        .clipped()
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
                }
            }
        }
        .frame(height: 8)
    }
}

#Preview("Progress · Active / Complete") {
    VStack(spacing: 24) {
        ConversionProgressBar(value: 0, isRunning: true)
        ConversionProgressBar(value: 0.42, isRunning: true)
        ConversionProgressBar(value: 1, isRunning: false)
    }
    .padding(24)
    .frame(width: 360)
}

