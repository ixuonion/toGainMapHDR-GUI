import SwiftUI

struct CommandDisplayView: View {
    let command: ConversionCommand?

    var body: some View {
        Text(attributedCommand)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var attributedCommand: AttributedString {
        guard let command else {
            var empty = AttributedString(L10n.text("add_images_to_build_command"))
            empty.foregroundColor = .secondary
            return empty
        }

        let tokens = [command.executable] + command.arguments
        var result = AttributedString()

        for (index, token) in tokens.enumerated() {
            if index > 0 {
                result += AttributedString(index.isMultiple(of: 2) ? " " : " \\\n  ")
            }

            var segment = AttributedString(Self.shellEscaped(token))
            if index == 0 {
                segment.foregroundColor = .accentColor
            } else if token.hasPrefix("-") {
                segment.foregroundColor = .purple
            } else if token.hasPrefix("/") {
                segment.foregroundColor = .secondary
            } else {
                segment.foregroundColor = .primary
            }
            result += segment
        }

        return result
    }

    private static func shellEscaped(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\"'\\$&;()[]{}<>|*?~`!")) != nil else {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
