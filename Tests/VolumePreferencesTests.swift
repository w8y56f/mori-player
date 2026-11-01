import Foundation

@main
struct VolumePreferencesTests {
    @MainActor
    static func main() {
        let suite = "MoriPlayer.VolumeTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let first = PlayerModel(preferences: preferences)
        let independent = PlayerModel(preferences: preferences)
        precondition(first.volume == 0.7 && first.player.volume == 0.7)
        precondition(preferences.object(forKey: VolumePreferences.lastVolumeKey) == nil,
                     "Initialization must not write remembered volume")
        first.volume = 0.35 // Slider binding uses this exact setter.
        precondition(preferences.double(forKey: VolumePreferences.lastVolumeKey) == 0.35)
        precondition(independent.volume == 0.7 && independent.player.volume == 0.7)
        let restored = PlayerModel(preferences: preferences)
        precondition(restored.volume == 0.35)
        restored.changeVolume(by: 0.05) // Both wheel and keyboard go through here.
        precondition(abs(preferences.double(forKey: VolumePreferences.lastVolumeKey) - 0.4) < 0.0001)
        restored.changeVolume(by: -1)
        precondition(restored.volume == 0 && restored.player.volume == 0)
        let muted = PlayerModel(preferences: preferences)
        precondition(muted.volume == 0)
        muted.volume = 0.42
        let saved = preferences.double(forKey: VolumePreferences.lastVolumeKey)

        preferences.set("fixed", forKey: "initialVolumeMode")
        let defaultFixed = PlayerModel(preferences: preferences)
        precondition(defaultFixed.volume == 0.7)
        preferences.set(0.25, forKey: VolumePreferences.fixedVolumeKey)
        let fixed = PlayerModel(preferences: preferences)
        precondition(fixed.volume == 0.25 && fixed.player.volume == 0.25)
        fixed.volume = 0.8
        precondition(preferences.double(forKey: VolumePreferences.fixedVolumeKey) == 0.25)
        precondition(preferences.double(forKey: VolumePreferences.lastVolumeKey) == saved)
        preferences.set(1.0, forKey: VolumePreferences.fixedVolumeKey)
        precondition(fixed.volume == 0.8 && independent.volume == 0.7)
        precondition(PlayerModel(preferences: preferences).volume == 1)
        preferences.set(0.0, forKey: VolumePreferences.fixedVolumeKey)
        precondition(PlayerModel(preferences: preferences).volume == 0)

        preferences.set("remember", forKey: "initialVolumeMode")
        precondition(PlayerModel(preferences: preferences).volume == 0.42)
        fixed.changeVolume(by: -0.05)
        precondition(abs(PlayerModel(preferences: preferences).volume - 0.75) < 0.0001,
                     "Existing windows must honor the current save policy on their next user adjustment")
        for key in [VolumePreferences.lastVolumeKey, VolumePreferences.fixedVolumeKey] {
            preferences.set(key == VolumePreferences.lastVolumeKey ? "remember" : "fixed", forKey: "initialVolumeMode")
            for invalid: Any in ["broken", -0.1, 1.1, Double.nan, true] {
                preferences.set(invalid, forKey: key)
                precondition(PlayerModel(preferences: preferences).volume == 0.7)
            }
        }
        preferences.set("invalid-mode", forKey: "initialVolumeMode")
        preferences.set(0.3, forKey: VolumePreferences.lastVolumeKey)
        precondition(PlayerModel(preferences: preferences).volume == 0.3)
        for model in [first, independent, restored, muted, defaultFixed, fixed] { model.closePlayback() }
        print("PASS: first-use 70%, slider/wheel/key save path, persisted restore, muted restore, independent windows, fixed mode isolation, live policy, invalid settings fallback.")
    }
}
