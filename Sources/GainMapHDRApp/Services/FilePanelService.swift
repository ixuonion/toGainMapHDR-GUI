import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanelService {
    static func pickImages() async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = L10n.text("add_hdr_images")
        panel.prompt = L10n.text("add_images")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = FileAccessService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        return await present(panel) == .OK ? panel.urls : []
    }

    static func pickFolder(title: String = L10n.text("choose_folder"), prompt: String = L10n.text("choose")) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        return await present(panel) == .OK ? panel.url : nil
    }

    private static func present(_ panel: NSOpenPanel) async -> NSApplication.ModalResponse {
        guard !Task.isCancelled else { return .cancel }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let window = NSApp.keyWindow {
                    panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                } else {
                    panel.begin { continuation.resume(returning: $0) }
                }
            }
        } onCancel: {
            // AppKit's sheet API is callback based; cancellation crosses to its main actor once.
            Task { @MainActor in panel.cancel(nil) }
        }
    }
}
