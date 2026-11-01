import SwiftUI

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTab = 0

    func showAbout() { selectedTab = 3 }
}
