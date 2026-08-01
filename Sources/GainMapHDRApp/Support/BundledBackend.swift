import Foundation

enum BundledBackend {
    static var executablePath: String {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("backend/toGainMapHDR"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }

        if let sourceURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GainMapHDRApp/Resources/backend/toGainMapHDR") as URL?,
           FileManager.default.isExecutableFile(atPath: sourceURL.path) {
            return sourceURL.path
        }

        return "toGainMapHDR"
    }

    static func workingDirectory(for executable: String) -> URL? {
        guard executable.contains("/") else { return nil }
        return URL(fileURLWithPath: executable).deletingLastPathComponent()
    }
}
