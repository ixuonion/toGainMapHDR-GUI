import AppKit
import SwiftUI

@main
struct GainMapHDRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ConversionStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("add_images") + "...") {
                    store.pickInputImages()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button(L10n.text("add_folder") + "...") {
                    store.pickInputFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu(L10n.text("convert_section")) {
                Button(L10n.text("convert")) {
                    store.startConversion()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!store.canConvert)

                Button(L10n.text("cancel")) {
                    store.cancelConversion()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isConverting)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
