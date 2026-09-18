import Foundation

enum BundledBackend {
    static var executablePath: String {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("backend/toGainMapHDR")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled.path }
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/backend/toGainMapHDR")
        return source.path
        #else
        return bundled?.path ?? "toGainMapHDR"
        #endif
    }
    static func workingDirectory(for executable: String) -> URL? {
        guard executable.contains("/") else { return nil }
        return URL(fileURLWithPath: executable).deletingLastPathComponent()
    }
}
