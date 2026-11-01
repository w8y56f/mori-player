import AVFoundation
import Foundation

@main
struct PlaybackPositionTests {
    @MainActor
    static func main() async throws {
        let suite = "MoriPlayer.PositionTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/position-test.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        // Defaults are not explicitly registered: position memory must be enabled by default.
        try await record(url, preferences, seconds: 8)
        try await assertResume(url, preferences, expected: 8)
        let saved = preferences.data(forKey: "playbackPositions.v1")
        precondition(saved != nil)
        preferences.set(false, forKey: "rememberPlaybackPosition")
        try await assertResume(url, preferences, expected: 0)
        try await record(url, preferences, seconds: 12)
        precondition(saved == preferences.data(forKey: "playbackPositions.v1"), "Disabled memory must not update saved history")
        preferences.set(true, forKey: "rememberPlaybackPosition")
        try await assertResume(url, preferences, expected: 8)
        try await stopAndForget(url, preferences)
        try await assertResume(url, preferences, expected: 0)
        try await record(url, preferences, seconds: 20)
        try await assertResume(url, preferences, expected: 0)
        try await record(url, preferences, seconds: 8)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: url.path)
        try await assertResume(url, preferences, expected: 0)
        preferences.set(Data("corrupt".utf8), forKey: "playbackPositions.v1")
        try await assertResume(url, preferences, expected: 0)
        print("PASS: persistent resume across new player instances, default enabled, disabled read/write, re-enable, stop/end reset, changed files, corrupt history.")
    }

    @MainActor
    static func load(_ url: URL, _ preferences: UserDefaults) async throws -> PlayerModel {
        let model = PlayerModel(preferences: preferences)
        model.open(url)
        try await wait { !model.isLoading }
        precondition(model.canPlay && model.errorMessage == nil)
        model.togglePlayback()
        return model
    }

    @MainActor
    static func record(_ url: URL, _ preferences: UserDefaults, seconds: Double) async throws {
        let model = try await load(url, preferences)
        model.seek(to: seconds)
        try await wait { abs(model.player.currentTime().seconds - seconds) < 0.1 }
        model.savePlaybackPosition()
    }

    @MainActor
    static func assertResume(_ url: URL, _ preferences: UserDefaults, expected: Double) async throws {
        let model = try await load(url, preferences)
        precondition(abs(model.player.currentTime().seconds - expected) < 0.5,
                     "Expected resume at \(expected), got \(model.player.currentTime().seconds)")
    }

    @MainActor
    static func stopAndForget(_ url: URL, _ preferences: UserDefaults) async throws {
        let model = try await load(url, preferences)
        model.stop()
        try await wait { model.player.currentTime().seconds < 0.1 }
        model.savePlaybackPosition()
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
