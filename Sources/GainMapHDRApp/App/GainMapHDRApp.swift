import AppKit
import SwiftUI

@main
struct GainMapHDRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ConversionStore()

    var body: some Scene {
        Window("GainMapHDR", id: "studio") {
            GeometryReader { _ in
                StudioView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 980, minHeight: 620)
            .onAppear { appDelegate.store = store }
            .onOpenURL { store.addInputURLs([$0]) }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("add_images") + "...") { store.pickInputImages() }
                    .keyboardShortcut("o", modifiers: [.command]).disabled(!store.canImport)
                Button(L10n.text("add_folder") + "...") { store.pickInputFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(!store.canImport)
            }
            CommandMenu(L10n.text("convert_section")) {
                Button(L10n.text("convert")) { store.startConversion() }
                    .keyboardShortcut(.return, modifiers: [.command]).disabled(!store.canConvert)
                Button(L10n.text("cancel")) { store.cancelConversion() }
                    .keyboardShortcut(".", modifiers: [.command]).disabled(!store.isConverting || store.isCancelling)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ConversionStore?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
