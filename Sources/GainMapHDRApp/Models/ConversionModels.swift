import Foundation

struct ImageInput: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var displayName: String {
        url.lastPathComponent
    }

    var directoryName: String {
        url.deletingLastPathComponent().lastPathComponent
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic: L10n.text("heic")
        }
    }
}

enum NamingPolicy: String, CaseIterable, Identifiable {
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

enum ColorSpaceOption: String, CaseIterable, Identifiable {
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

enum BitDepthOption: Int, CaseIterable, Identifiable {
    case eight = 8
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)-bit"
    }
}

enum DestinationChoice: String, CaseIterable, Identifiable {
    case sourceFolder
    case pictures
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceFolder: L10n.text("source_folder")
        case .pictures: L10n.text("pictures")
        case .custom: L10n.text("choose_folder_ellipsis")
        }
    }
}

struct ConversionSettings: Equatable {
    var format: OutputFormat = .heic
    var namingPolicy: NamingPolicy = .appendHDR
    var colorSpace: ColorSpaceOption = .rec2020
    var bitDepth: BitDepthOption = .eight
    var quality: Int = 85
    var concurrency: Int = max(1, min(ProcessInfo.processInfo.processorCount, 4))
    var destinationChoice: DestinationChoice = .sourceFolder
    var customDestination: URL?
    var backendExecutable: String = BundledBackend.executablePath
    var toneMappingRatio: Double = 3.0
    var maxHeadroom: Double = 6.0
    var outputMode: OutputMode = .isoGainMap
    var subsampleGainMap = false
    var monochromeGainMap = false

    mutating func clampValues() {
        quality = min(100, max(1, quality))
        concurrency = min(max(ProcessInfo.processInfo.processorCount, 1), max(1, concurrency))
        toneMappingRatio = min(100, max(1, toneMappingRatio))
        maxHeadroom = min(100, max(1, maxHeadroom))
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
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

struct ConversionCommand: Equatable {
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

struct ConversionRequest: Equatable {
    var inputs: [ImageInput]
    var settings: ConversionSettings

    var isBatch: Bool { inputs.count > 1 }

    var outputURL: URL? {
        switch settings.destinationChoice {
        case .sourceFolder:
            return inputs.first?.url.deletingLastPathComponent()
        case .pictures:
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        case .custom:
            return settings.customDestination
        }
    }

    func command(for input: ImageInput) -> ConversionCommand? {
        guard let outputURL else {
            return nil
        }

        var effectiveSettings = settings
        effectiveSettings.clampValues()

        var arguments: [String] = [
            input.url.path,
            outputURL.path,
            "-q", String(format: "%.2f", Double(effectiveSettings.quality) / 100.0),
            "-r", String(format: "%.1f", effectiveSettings.toneMappingRatio),
            "-R", String(format: "%.1f", effectiveSettings.maxHeadroom),
            "-c", effectiveSettings.colorSpace.rawValue,
            "-d", String(effectiveSettings.bitDepth.rawValue),
            "-t", effectiveSettings.namingPolicy.rawValue
        ]

        if let flag = effectiveSettings.outputMode.cliFlag {
            arguments.append(flag)
        }

        if effectiveSettings.subsampleGainMap {
            arguments.append(contentsOf: ["-H", "2"])
        }

        if effectiveSettings.monochromeGainMap {
            arguments.append("-m")
        }

        return ConversionCommand(executable: effectiveSettings.backendExecutable, arguments: arguments)
    }

    func representativeCommand() -> ConversionCommand? {
        guard let input = inputs.first else { return nil }
        return command(for: input)
    }
}
