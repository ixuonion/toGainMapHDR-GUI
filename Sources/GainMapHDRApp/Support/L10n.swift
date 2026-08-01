import Foundation
import SwiftUI

enum L10n {
    private static let resourceBundle: Bundle = {
        let bundleName = "GainMapHDR_GainMapHDRApp"

        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent(bundleName)
            .appendingPathExtension("bundle"),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }

        return .module
    }()

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: resourceBundle, comment: "")
    }
}

enum AppTypography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let subsectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let auxiliary = Font.system(size: 11)
}
