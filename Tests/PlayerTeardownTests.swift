import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Exercises destruction, not just window.close() while tests retain controllers.
@main
struct PlayerTeardownTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let suite = "MoriPlayer.TeardownTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }

        let model = PlayerModel(preferences: preferences)
        model.changeSpeed(by: 0.25)
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        let surface = PlaybackSurface()
        surface.model = model
        // dismantle must only release native resources. Publishing here re-enters
        // the same SwiftUI graph while it is being destroyed (the reported crash).
        PlayerSurface.dismantleNSView(surface, coordinator: ())
        PlayerSurface.dismantleNSView(surface, coordinator: ())
        precondition(changes == 0, "Native view teardown must not publish model changes")
        precondition(model.isSpeedVisible, "Dismantling a view must not change player-owned hints")
        model.cancelPresentationTasks()
        withExtendedLifetime(subscription) {}

        for _ in 0..<12 {
            let player = PlayerModel(preferences: preferences)
            player.changeSpeed(by: 0.25)
            var oldHost: NSHostingView<PlayerSurface>?
            weak var releasedHost: NSHostingView<PlayerSurface>?
            autoreleasepool {
                oldHost = NSHostingView(rootView: PlayerSurface(model: player))
                releasedHost = oldHost
                oldHost?.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
                oldHost?.layoutSubtreeIfNeeded()
                oldHost = nil
            }
            drainRunLoop()
            precondition(releasedHost == nil, "The SwiftUI host must actually be destroyed")
            player.closePlayback()
        }

        preferences.set(true, forKey: "allowMultipleWindows")
        let manager = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false, requestTermination: {})
        weak var releasedController: PlayerWindowController?
        autoreleasepool {
            let controller = manager.ensureWindow()
            releasedController = controller
            controller.player.changeSpeed(by: 0.25)
            controller.close()
        }
        try await Task.sleep(for: .milliseconds(100))
        drainRunLoop()
        precondition(manager.controllers.isEmpty && releasedController == nil)
        try await tabCloseChecks(preferences: preferences)
        print("PASS: idempotent teardown without model publication, repeated SwiftUI host destruction, controller release after close, native tab-group closure with surviving players.")
    }

    @MainActor
    static func tabCloseChecks(preferences: UserDefaults) async throws {
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/tab-close-test.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: fixture, settings: format.settings)
            try file.write(from: buffer)
        }
        for closingIndex in [1, 0, 2] {
            let manager = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false, requestTermination: {})
            manager.ensureWindow()
            manager.newWindow()
            manager.newWindow()
            for controller in manager.controllers { controller.player.open(fixture) }
            let deadline = ContinuousClock.now + .seconds(10)
            while manager.controllers.contains(where: { $0.player.isLoading }) {
                precondition(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(30))
            }
            // Explicitly form native tabs, not just three unrelated NSWindows.
            autoreleasepool {
                let windows = manager.controllers.map { $0.window! }
                // AppKit may order a surviving tab front when its sibling closes.
                // Keep native tab behavior while rendering no desktop pixels and
                // accepting no mouse input, even if AppKit marks a tab visible.
                for window in windows {
                    window.alphaValue = 0
                    window.ignoresMouseEvents = true
                }
                windows[0].addTabbedWindow(windows[1], ordered: .above)
                windows[0].addTabbedWindow(windows[2], ordered: .above)
                precondition(windows[0].tabGroup?.windows.count == 3)
                windows[0].tabGroup?.selectedWindow = windows[1]
                precondition(windows.allSatisfy { $0.alphaValue == 0 && $0.ignoresMouseEvents })
            }
            weak var releasedTab: PlayerWindowController?
            autoreleasepool {
                let closing = manager.controllers[closingIndex]
                releasedTab = closing
                closing.player.changeSpeed(by: 0.25)
                closing.close()
            }
            try await Task.sleep(for: .milliseconds(150))
            drainRunLoop()
            precondition(releasedTab == nil, "The closed tab's controller must be released")
            precondition(manager.controllers.count == 2)
            precondition(manager.controllers.allSatisfy { $0.window?.alphaValue == 0 })
            precondition(manager.controllers.allSatisfy { $0.player.isPlaying && $0.player.canPlay })
            let before = manager.controllers.map { Double($0.player.player.time.intValue) / 1000 }
            // VLC publishes time in coarser intervals than AVPlayer.
            try await Task.sleep(for: .milliseconds(800))
            for (controller, time) in zip(manager.controllers, before) {
                precondition(Double(controller.player.player.time.intValue) / 1000 > time + 0.05,
                             "Closing one tab must not interrupt the other players")
            }
            for controller in Array(manager.controllers) { controller.close() }
            try await Task.sleep(for: .milliseconds(100))
            drainRunLoop()
            precondition(manager.controllers.isEmpty)
        }
    }

    @MainActor
    static func drainRunLoop() {
        autoreleasepool {
            let deadline = Date().addingTimeInterval(0.05)
            while Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: deadline)
            }
        }
    }
}
