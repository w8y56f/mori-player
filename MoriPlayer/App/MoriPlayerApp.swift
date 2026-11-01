import SwiftUI

@main
struct MoriPlayerApp: App {
    @NSApplicationDelegateAdaptor(PlayerAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appearanceController: appDelegate.coordinator.appearanceController)
        }
        .commands { PlayerCommands(coordinator: appDelegate.coordinator) }
    }
}

private struct PlayerCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @AppStorage("appLanguage") private var appLanguage = "system"
    @ObservedObject var coordinator: PlayerWindowCoordinator
    @AppStorage("allowMultipleWindows") private var allowMultipleWindows = false

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("关于") + " " + AppBuildInfo.read().name) {
                SettingsNavigation.shared.showAbout()
                openSettings()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button(L("新建播放窗口"), action: coordinator.newWindow)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!allowMultipleWindows)
            Button(L("打开文件…")) { coordinator.openFile() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu(L("播放")) {
            Button(coordinator.activePlayer?.isPlaying == true ? L("暂停") : L("播放")) {
                coordinator.activePlayer?.togglePlayback()
            }.disabled(coordinator.activePlayer?.canPlay != true)
            Button(L("停止")) { coordinator.activePlayer?.stop() }
                .disabled(coordinator.activePlayer?.canPlay != true)
            Divider()
            Button(L("切换全屏")) { coordinator.activePlayer?.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.control, .command])
                .disabled(coordinator.activePlayer == nil)
        }
        CommandGroup(after: .windowArrangement) {
            Button(L("显示播放器")) { coordinator.ensureWindow() }
        }
    }
}

@MainActor
final class PlayerAppDelegate: NSObject, NSApplicationDelegate {
    private let languageMenus = LanguageMenuController()
    let coordinator = PlayerWindowCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.ensureWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator.openURLs(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.ensureWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.saveAllPositions()
    }
}
