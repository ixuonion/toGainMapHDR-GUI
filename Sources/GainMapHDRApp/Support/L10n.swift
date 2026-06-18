import Foundation
import SwiftUI

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}

enum AppTypography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let subsectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let auxiliary = Font.system(size: 11)
}
