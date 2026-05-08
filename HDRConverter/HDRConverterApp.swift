import SwiftUI
import AppKit

@main
struct HDRConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandMenu("帮助") {
                Button("打开上游项目") {
                    openURL("https://github.com/chemharuka/toGainMapHDR")
                }
                Button("打开 macOS 设计指南") {
                    openURL("https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/")
                }
            }
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
