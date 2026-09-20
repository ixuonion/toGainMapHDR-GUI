import Foundation

struct ImageInput: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL

    var displayName: String {
        url.lastPathComponent
    }

    var directoryName: String {
        url.deletingLastPathComponent().lastPathComponent
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic: L10n.text("heic")
        }
    }
}

enum NamingPolicy: String, CaseIterable, Identifiable, Sendable {
    case appendHDR = "-HDR"
    case appendAdaptiveHDR = "-AdaptiveHDR"
    case appendAppleHDR = "-AppleHDR"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appendHDR: L10n.text("append_hdr")
        case .appendAdaptiveHDR: L10n.text("append_adaptive_hdr")
        case .appendAppleHDR: L10n.text("append_apple_hdr")
        }
    }
}

enum ColorSpaceOption: String, CaseIterable, Identifiable, Sendable {
    case srgb
    case p3
    case rec2020

    var id: String { rawValue }

    var title: String {
        switch self {
        case .srgb: L10n.text("srgb")
        case .p3: L10n.text("display_p3")
        case .rec2020: L10n.text("rec2020")
        }
    }
}

enum BitDepthOption: Int, CaseIterable, Identifiable, Sendable {
    case eight = 8
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)-bit"
    }
}

enum DestinationChoice: String, CaseIterable, Identifiable, Sendable {
    case sourceFolder
    case pictures
    case photosLibrary
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceFolder: L10n.text("source_folder")
        case .photosLibrary: L10n.text("photos_library")
        case .pictures: L10n.text("pictures")
        case .custom: L10n.text("choose_folder_ellipsis")
        }
    }
}

struct ConversionSettings: Equatable, Sendable {
    var format: OutputFormat = .heic
    var namingPolicy: NamingPolicy = .appendHDR
    var colorSpace: ColorSpaceOption = .rec2020
    var bitDepth: BitDepthOption = .eight
    var quality: Int = 85
    /// Zero selects the measured, memory-limited Auto policy.
    var concurrency: Int = 0
    var destinationChoice: DestinationChoice = .sourceFolder
    var customDestination: URL?
    var backendExecutable: String = "toGainMapHDR"
    var toneMappingRatio: Double = 3.0
    var maxHeadroom: Double = 6.0
    var outputMode: OutputMode = .isoGainMap
    var subsampleGainMap = false
    var monochromeGainMap = false

    var displayMonochrome: Bool {
        get { outputMode == .isoGainMap && monochromeGainMap }
        set { monochromeGainMap = newValue }
    }
    var qualityValue: Double {
        get { Double(quality) }
        set { quality = newValue.isFinite ? Int(min(100, max(1, newValue)).rounded()) : 85 }
    }
    var displayBitDepth: BitDepthOption {
        get { effectiveBitDepth }
        set { bitDepth = newValue }
    }
    var effectiveBitDepth: BitDepthOption { outputMode == .pqHDR ? .ten : bitDepth }

    mutating func clampValues() {
        quality = min(100, max(1, quality))
        concurrency = min(8, max(0, concurrency))
        toneMappingRatio = toneMappingRatio.isFinite ? min(100, max(1, toneMappingRatio)) : 3
        maxHeadroom = maxHeadroom.isFinite ? min(100, max(1, maxHeadroom)) : 6
    }
}

enum OutputMode: String, CaseIterable, Identifiable, Sendable {
    case isoGainMap
    case appleGainMap
    case pqHDR
    case hlgHDR
    case sdr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isoGainMap: L10n.text("iso_gain_map")
        case .appleGainMap: L10n.text("apple_gain_map")
        case .pqHDR: L10n.text("pq_hdr")
        case .hlgHDR: L10n.text("hlg_hdr")
        case .sdr: L10n.text("tone_mapped_sdr")
        }
    }

    var cliFlag: String? {
        switch self {
        case .isoGainMap: nil
        case .appleGainMap: "-g"
        case .pqHDR: "-p"
        case .hlgHDR: "-h"
        case .sdr: "-s"
        }
    }
}

struct ConversionCommand: Equatable, Sendable {
    var executable: String
    var arguments: [String]

    var displayString: String {
        ([executable] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\"'\\$&;()[]{}<>|*?~`!")) != nil else {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct ConversionRequest: Equatable, Sendable {
    var inputs: [ImageInput]
    var settings: ConversionSettings

    var isBatch: Bool { inputs.count > 1 }

    var outputURL: URL? {
        switch settings.destinationChoice {
        case .photosLibrary:
            return nil
        case .sourceFolder:
            return inputs.first?.url.deletingLastPathComponent()
        case .pictures:
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        case .custom:
            return settings.customDestination
        }
    }

    func command(for input: ImageInput, outputDirectory: URL? = nil) -> ConversionCommand? {
        guard let outputURL = outputDirectory ?? outputURL else {
            return nil
        }

        var effectiveSettings = settings
        effectiveSettings.clampValues()

        var arguments: [String] = [
            input.url.path,
            outputURL.path,
            "-q", String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(effectiveSettings.quality) / 100.0),
            "-r", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), effectiveSettings.toneMappingRatio),
            "-R", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), effectiveSettings.maxHeadroom),
            "-c", effectiveSettings.colorSpace.rawValue,
            "-d", String(effectiveSettings.effectiveBitDepth.rawValue),
            "-t", effectiveSettings.namingPolicy.rawValue
        ]

        if let flag = effectiveSettings.outputMode.cliFlag {
            arguments.append(flag)
        }

        if effectiveSettings.subsampleGainMap {
            arguments.append("-H")
        }

        if effectiveSettings.monochromeGainMap && effectiveSettings.outputMode == .isoGainMap {
            arguments.append("-m")
        }

        return ConversionCommand(executable: effectiveSettings.backendExecutable, arguments: arguments)
    }

    func outputFilename(for input: ImageInput) -> String {
        input.url.deletingPathExtension().lastPathComponent + settings.namingPolicy.rawValue + ".heic"
    }

    func outputFile(for input: ImageInput) -> URL? {
        outputURL?.appendingPathComponent(outputFilename(for: input))
    }

    func representativeCommand() -> ConversionCommand? {
        guard let input = inputs.first else { return nil }
        return command(for: input)
    }
}
