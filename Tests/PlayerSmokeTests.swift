import AppKit
import AVFoundation

/// Integration checks against a generated local media file and the real AVPlayer.
@main
struct PlayerSmokeTests {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = directory.appendingPathComponent("smoke-test.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: fixture, settings: format.settings)
            try file.write(from: buffer)
        }

        let suiteName = "MoriPlayer.SmokeTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = PlayerModel(preferences: preferences)
        model.open(fixture)
        try await wait { !model.isLoading }
        precondition(model.errorMessage == nil && model.canPlay)
        precondition(abs(model.duration - 20) < 0.1)
        try await wait { model.elapsed > 0.1 }
        model.togglePlayback()
        precondition(!model.isPlaying)
        model.seek(to: 8)
        try await wait { abs(model.player.currentTime().seconds - 8) < 0.1 }
        model.seek(by: -5)
        try await wait { abs(model.player.currentTime().seconds - 3) < 0.1 }
        model.seek(by: 5)
        try await wait { abs(model.player.currentTime().seconds - 8) < 0.1 }
        model.stop()
        try await wait { model.player.currentTime().seconds < 0.1 }
        precondition(!model.isPlaying && model.elapsed < 0.1)
        model.changeVolume(by: 100)
        precondition(model.volume == 1 && model.player.volume == 1)
        model.changeVolume(by: -100)
        precondition(model.volume == 0 && model.player.volume == 0)
        model.changeSpeed(by: 0.25)
        precondition(model.speed == 1.25)
        model.togglePlayback()
        precondition(model.player.rate == 1.25)
        model.changeSpeed(by: 100)
        precondition(model.speed == 4)
        model.changeSpeed(by: -100)
        precondition(model.speed == 0.25)
        model.changeSpeed(by: 0.75)
        model.seek(to: 19.8)
        try await wait { !model.isPlaying }
        model.togglePlayback()
        try await wait { model.elapsed < 2 && model.elapsed > 0.1 }
        precondition(model.isPlaying)
        model.stop()
        model.seek(to: -100)
        precondition(model.elapsed == 0)
        model.seek(to: 100)
        precondition(model.elapsed == 20)
        precondition(PlayerModel.time(3661) == "1:01:01")
        precondition(PlayerModel.time(.nan) == "00:00")
        let invalid = directory.appendingPathComponent("invalid-media.wav")
        try Data("invalid".utf8).write(to: invalid)
        model.changeSpeed(by: 0.25)
        precondition(model.isSpeedVisible)
        model.open(invalid)
        precondition(!model.isSpeedVisible, "Replacing a file must dismiss an old speed hint")
        try await wait { !model.isLoading }
        precondition(model.errorMessage != nil && !model.canPlay)
        let previousVolume = model.volume
        model.open(invalid)
        model.open(fixture)
        try await wait { !model.isLoading }
        precondition(model.errorMessage == nil && model.canPlay)
        precondition(model.volume == previousVolume, "Replacing media in a window must keep its current volume")
        model.stop()
        print("PASS: real media loading, playback, pause, ±5-second seeks, stop, volume/speed limits, end/replay, invalid media, rapid replacement, time formatting.")
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for AVPlayer")
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
