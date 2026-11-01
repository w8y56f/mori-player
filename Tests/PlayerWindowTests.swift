import AppKit
import AVFoundation
import Foundation

/// Real controllers and players, but windows are never shown or activated.
@main
struct PlayerWindowTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let suite = "MoriPlayer.WindowTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        let a = directory.appendingPathComponent("window-a.wav")
        let b = directory.appendingPathComponent("window-b.wav")
        try fixture(a)
        try fixture(b)
        let manager = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false, requestTermination: {})
        precondition(!manager.allowsMultipleWindows)
        let first = manager.ensureWindow()
        manager.newWindow()
        precondition(manager.controllers.count == 1)
        manager.openURLs([a, b])
        try await wait { !first.player.isLoading }
        precondition(first.player.fileName == a.lastPathComponent && first.player.canPlay)
        precondition(first.player.playbackHint == .play)
        first.player.togglePlayback()
        precondition(first.player.playbackHint == .pause && !first.player.isPlaying)
        try await Task.sleep(for: .milliseconds(650))
        first.player.togglePlayback()
        precondition(first.player.playbackHint == .play)
        try await Task.sleep(for: .milliseconds(650))
        precondition(first.player.playbackHint == .play, "An old hint timer must not hide a new one")
        try await Task.sleep(for: .milliseconds(500))
        precondition(first.player.playbackHint == nil)
        first.player.togglePlayback()
        first.player.stop()
        precondition(first.player.playbackHint == nil && !first.player.isPlaying)

        preferences.set(true, forKey: "allowMultipleWindows")
        manager.openURLs([b], from: first)
        precondition(manager.controllers.count == 2)
        let second = manager.controllers[1]
        try await wait { !second.player.isLoading }
        precondition(first.player !== second.player && first.player.player !== second.player.player)
        precondition(first.player.fileName == a.lastPathComponent && second.player.fileName == b.lastPathComponent)
        first.player.togglePlayback()
        precondition(first.player.isPlaying && second.player.isPlaying)
        first.player.volume = 0.2
        first.player.changeSpeed(by: 0.25)
        first.player.isPinned = true
        precondition(second.player.volume == 0.7 && second.player.speed == 1 && !second.player.isPinned)
        manager.didFocus(first)
        precondition(manager.activePlayer === first.player)
        manager.didResignFocus(first)
        precondition(manager.activePlayer == nil)
        manager.didFocus(second)
        precondition(manager.activePlayer === second.player)

        first.player.togglePlayback()
        second.player.togglePlayback()
        first.player.seek(to: 3)
        second.player.seek(to: 7)
        try await wait { abs(first.player.player.currentTime().seconds - 3) < 0.1 && abs(second.player.player.currentTime().seconds - 7) < 0.1 }
        manager.saveAllPositions()
        let history = try JSONSerialization.jsonObject(with: preferences.data(forKey: "playbackPositions.v1")!) as! [String: Any]
        precondition(history[a.path] != nil && history[b.path] != nil, "Independent windows must merge their history writes")

        manager.newWindow()
        let empty = manager.controllers.last!
        precondition(manager.controllers.count == 3 && empty.player.fileName == nil)
        manager.didFocus(empty)
        manager.openURLs([a])
        precondition(manager.controllers.count == 3 && empty.player.fileName == a.lastPathComponent)
        try await wait { !empty.player.isLoading }
        manager.openURLs([a])
        precondition(manager.controllers.count == 4, "Opening the same file again must create an independent player")
        let duplicate = manager.controllers.last!
        try await wait { !duplicate.player.isLoading }
        // A drop calls this player's open method directly, regardless of the mode.
        first.player.open(b)
        try await wait { !first.player.isLoading }
        precondition(manager.controllers.count == 4 && first.player.fileName == b.lastPathComponent)

        preferences.set(false, forKey: "allowMultipleWindows")
        manager.didFocus(first)
        manager.openURLs([a])
        try await wait { !first.player.isLoading }
        precondition(manager.controllers.count == 4 && first.player.fileName == a.lastPathComponent)
        manager.newWindow()
        precondition(manager.controllers.count == 4)
        second.close()
        precondition(manager.controllers.count == 3 && !second.player.canPlay && !second.player.isPlaying)
        precondition(second.player.playbackHint == nil)
        for controller in Array(manager.controllers) { controller.close() }
        precondition(manager.controllers.isEmpty)
        let reopened = manager.ensureWindow()
        precondition(manager.controllers.count == 1 && reopened.player.fileName == nil)
        reopened.close()
        print("PASS: single/multi-window routing, empty reuse, independent simultaneous playback, focused commands, merged history, hint timers, targeted drops, safe mode changes, close/reopen cleanup.")
    }

    static func fixture(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for AVPlayer")
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}
