import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .light: L("浅色 Light")
        case .dark: L("深色 Dark")
        }
    }

}
