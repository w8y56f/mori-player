import SwiftUI

@main
struct MoriPlayerApp: App {
    @StateObject private var player = PlayerModel()

    var body: some Scene {
        Window("Mori Player", id: "player") {
            PlayerWindowView(model: player)
                .onOpenURL { player.open($0) }
        }
        .defaultSize(width: 1040, height: 650)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…", action: player.openFile)
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("播放") {
                Button(player.isPlaying ? "暂停" : "播放", action: player.togglePlayback)
                    .disabled(!player.canPlay)
                Button("停止", action: player.stop).disabled(!player.canPlay)
                Divider()
                Button("切换全屏", action: player.toggleFullScreen)
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
        Settings { SettingsView() }
    }
}
