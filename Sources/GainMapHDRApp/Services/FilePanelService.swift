import AppKit
import UniformTypeIdentifiers

enum FilePanelService {
    @MainActor
    static func pickImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = L10n.text("add_hdr_images")
        panel.prompt = L10n.text("add_images")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedImageTypes
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    static func pickFolder(title: String = L10n.text("choose_folder"), prompt: String = L10n.text("choose")) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func imageFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static let supportedImageTypes: [UTType] = [
        .png,
        .tiff,
        .heic,
        .heif,
        .jpeg,
        UTType(filenameExtension: "avif"),
        UTType(filenameExtension: "jxl"),
        UTType(filenameExtension: "exr"),
        UTType(filenameExtension: "hdr")
    ].compactMap { $0 }

    private static let supportedExtensions = Set([
        "png", "tif", "tiff", "heic", "heif", "jpg", "jpeg", "avif", "jxl", "exr", "hdr"
    ])
}
