import AppKit
import VLCKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var seekHint: String?
    private var seekHintTask: Task<Void, Never>?
    @Published private(set) var volumeHint: Int?
    private var volumeHintTask: Task<Void, Never>?
    var seekStep: Int { let n = preferences.integer(forKey: "seekStepSeconds"); return (1...60).contains(n) ? n : 5 }
    func clearCentralHints() {
        hidePlaybackHint()
        seekHintTask?.cancel(); seekHint = nil
        volumeHintTask?.cancel(); volumeHint = nil
    }
    func skip(forward: Bool) {
        guard canPlay, player.isSeekable else { return }
        let delta = Double(seekStep) * (forward ? 1 : -1)
        let target = min(max(elapsed + delta, 0), duration)
        guard abs(target - elapsed) > 0.01 else { return }
        clearCentralHints(); subtitles.dismissFeedback()
        seek(to: target)
        seekHint = L(forward ? "快进" : "快退") + " \(seekStep) " + L("秒")
        seekHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.seekHint = nil
        }
    }
    let player = VLCMediaPlayer()
    let subtitles: SubtitleController
    struct VideoPresentation {
        let mediaID: UUID
        let pixels: CGSize
    }
    @Published private(set) var videoPresentation: VideoPresentation?
    @Published var initialVideoPixelLimit: CGSize?
    weak var videoViewport: NSView?
    var currentMediaID: UUID { loadID }
    private var pendingResume = true
    @Published var fileName: String?
    @Published var elapsed = 0.0
    @Published var duration = 0.0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var speed: Float = 1
    @Published private(set) var isSpeedVisible = false
    enum PlaybackHint: String { case play = "play.fill", pause = "pause.fill" }
    @Published private(set) var playbackHint: PlaybackHint?
    private var playbackHintTask: Task<Void, Never>?
    @Published private(set) var isFullScreen = false
    @Published private(set) var areControlsVisible = true
    private var speedHintTask: Task<Void, Never>?
    private var controlsHideTask: Task<Void, Never>?
    private var isHoveringControls = false
    private var subtitleMenuVisible = false
    func setSubtitleMenuVisible(_ visible: Bool) {
        subtitleMenuVisible = visible
        if visible { areControlsVisible = true }
        scheduleControlsHide()
    }
    private var isInteractingWithControls = false
    @Published var volume: Double = 0.7 {
        didSet {
            let bounded = volume.isFinite ? min(max(volume, 0), 1) : VolumePreferences.defaultVolume
            if volume != bounded { volume = bounded }
            player.audio?.volume = Int32((bounded * 100).rounded())
            if bounded != oldValue { showVolumeHint(bounded) }
            if bounded != oldValue, InitialVolumeMode.read(from: preferences) == .remember {
                preferences.set(bounded, forKey: VolumePreferences.lastVolumeKey)
            }
        }
    }
    @Published var errorMessage: String?
    @Published var isPinned = false {
        didSet { updateWindowLevel() }
    }
    weak var window: NSWindow? {
        didSet { updateWindowLevel() }
    }
    private var polling: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var scopedURL: URL?
    private var loadID = UUID()
    private var seekID = UUID()
    private var isSeeking = false
    private var seekRequestedAt = Date.distantPast
    private let preferences: UserDefaults
    private var currentURL: URL?
    private var currentFileMetadata: URLResourceValues?
    private var lastPositionSave = Date.distantPast
    private var positions: [String: PlaybackPosition]

    private struct PlaybackPosition: Codable {
        let seconds: Double
        let duration: Double
        let fileSize: Int?
        let modifiedAt: Date?
        let savedAt: Date
    }

    private var remembersPlaybackPosition: Bool {
        preferences.object(forKey: "rememberPlaybackPosition") as? Bool ?? true
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        subtitles = SubtitleController(player: player, preferences: preferences)
        if let data = preferences.data(forKey: "playbackPositions.v1"),
           let records = try? JSONDecoder().decode([String: PlaybackPosition].self, from: data) {
            positions = records
        } else {
            positions = [:]
        }
        volume = VolumePreferences.initialVolume(in: preferences)
        player.audio?.volume = Int32((volume * 100).rounded())
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    deinit {
        polling?.cancel()
        loading?.cancel()
        speedHintTask?.cancel()
        controlsHideTask?.cancel()
        playbackHintTask?.cancel()
        volumeHintTask?.cancel()
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    var canPlay: Bool { player.media != nil && !isLoading }

    func open(_ url: URL) {
        clearCentralHints()
        savePlaybackPosition()
        currentURL = nil
        currentFileMetadata = nil
        hideSpeedHint()
        hidePlaybackHint()
        loading?.cancel()
        pendingResume = true
        videoPresentation = nil
        initialVideoPixelLimit = nil
        player.pause()
        player.stop()
        player.media = nil
        subtitles.reset()
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        let id = UUID()
        loadID = id
        seekID = UUID()
        isSeeking = false
        elapsed = 0
        duration = 0
        isPlaying = false
        isLoading = true
        fileName = url.lastPathComponent
        errorMessage = nil
        currentURL = url
        var metadataURL = url
        metadataURL.removeAllCachedResourceValues()
        currentFileMetadata = try? metadataURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        subtitles.reset(video: url)
        player.media = VLCMedia(url: url)
        player.media?.addOption(":sub-autodetect-file=0")
        player.media?.addOption(":subsdec-encoding=UTF-8")
        player.play()
        player.rate = speed
    }

    func togglePlayback() {
        guard canPlay else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            savePlaybackPosition()
            showPlaybackHint(.pause)
        } else {
            if elapsed >= duration - 0.1 { seek(to: 0) }
            player.play()
            player.rate = speed
            isPlaying = true
            showPlaybackHint(.play)
        }
    }

    func stop() {
        clearCentralHints()
        guard canPlay else { return }
        hidePlaybackHint()
        player.pause()
        isPlaying = false
        seek(to: 0)
        savePlaybackPosition()
    }

    func seek(by seconds: Double) { seek(to: elapsed + seconds) }

    func seek(to seconds: Double) {
        guard canPlay else { return }
        let target = min(max(seconds, 0), duration)
        let id = UUID()
        seekID = id
        isSeeking = true
        elapsed = target
        player.time = VLCTime(int: Int32(min(target * 1000, Double(Int32.max))))
        seekRequestedAt = Date()
        savePlaybackPosition()
    }

    private func savedPosition(for url: URL, duration: Double) -> Double {
        positions = readPositions()
        guard remembersPlaybackPosition,
              let record = positions[url.standardizedFileURL.path],
              record.seconds.isFinite, record.seconds > 0,
              record.seconds < duration - 0.5,
              abs(record.duration - duration) < 1 else { return 0 }
        guard record.fileSize == currentFileMetadata?.fileSize,
              record.modifiedAt == currentFileMetadata?.contentModificationDate else { return 0 }
        return record.seconds
    }

    /// UserDefaults is persisted in the app's Preferences directory, not a cache.
    /// Save on transitions and every five seconds, bounding the history to 200 files.
    func savePlaybackPosition() {
        guard remembersPlaybackPosition, canPlay, let url = currentURL else { return }
        let seconds = elapsed
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        positions = readPositions()
        let key = url.standardizedFileURL.path
        if seconds <= 0.1 || seconds >= duration - 0.5 {
            positions.removeValue(forKey: key)
        } else {
            positions[key] = PlaybackPosition(seconds: seconds, duration: duration,
                fileSize: currentFileMetadata?.fileSize, modifiedAt: currentFileMetadata?.contentModificationDate, savedAt: Date())
        }
        if positions.count > 200 {
            positions = Dictionary(uniqueKeysWithValues: positions.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(200).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(positions) {
            preferences.set(data, forKey: "playbackPositions.v1")
        }
        lastPositionSave = Date()
    }

    private func readPositions() -> [String: PlaybackPosition] {
        guard let data = preferences.data(forKey: "playbackPositions.v1"),
              let records = try? JSONDecoder().decode([String: PlaybackPosition].self, from: data) else { return [:] }
        return records
    }

    private func showPlaybackHint(_ hint: PlaybackHint) {
        seekHintTask?.cancel(); seekHint = nil; subtitles.dismissFeedback()
        playbackHintTask?.cancel()
        playbackHint = hint
        playbackHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.playbackHint = nil
        }
    }

    private func hidePlaybackHint() {
        playbackHintTask?.cancel()
        playbackHintTask = nil
        playbackHint = nil
    }

    /// Used when a player window closes. Unlike Stop, this keeps its resume point.
    func closePlayback() {
        savePlaybackPosition()
        loadID = UUID()
        seekID = UUID()
        loading?.cancel()
        pendingResume = true
        polling?.cancel()
        cancelPresentationTasks()
        player.pause()
        player.stop()
        player.media = nil
        subtitles.reset()
        isPlaying = false
        isLoading = false
        currentURL = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    func changeVolume(by delta: Double) { volume = min(max(volume + delta, 0), 1) }

    private func showVolumeHint(_ value: Double) {
        hidePlaybackHint()
        seekHintTask?.cancel(); seekHint = nil
        subtitles.dismissFeedback()
        volumeHintTask?.cancel()
        volumeHint = Int((value * 100).rounded())
        volumeHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.volumeHint = nil
        }
    }

    func changeSpeed(by delta: Float) {
        speed = min(max(speed + delta, 0.25), 4)
        if isPlaying { player.play()
            player.rate = speed }
        speedHintTask?.cancel()
        isSpeedVisible = true
        speedHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.isSpeedVisible = false
        }
    }

    func hideSpeedHint() {
        speedHintTask?.cancel()
        speedHintTask = nil
        isSpeedVisible = false
    }

    func setFullScreen(_ fullScreen: Bool) {
        guard isFullScreen != fullScreen else { return }
        isFullScreen = fullScreen
        controlsHideTask?.cancel()
        areControlsVisible = !fullScreen
        isHoveringControls = false
        isInteractingWithControls = false
        updateWindowLevel()
    }

    func pointerMoved() {
        guard isFullScreen else { return }
        areControlsVisible = true
        scheduleControlsHide()
    }

    func setControlsHovered(_ hovered: Bool) {
        isHoveringControls = hovered
        if hovered { areControlsVisible = true }
        scheduleControlsHide()
    }

    func setControlsInteracting(_ interacting: Bool) {
        isInteractingWithControls = interacting
        if interacting { areControlsVisible = true }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = nil
        guard isFullScreen, !isHoveringControls, !isInteractingWithControls, !subtitleMenuVisible else { return }
        controlsHideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, self.isFullScreen,
                  !self.isHoveringControls, !self.isInteractingWithControls, !self.subtitleMenuVisible else { return }
            self.areControlsVisible = false
        }
    }

    func cancelPresentationTasks() {
        clearCentralHints()
        hideSpeedHint()
        hidePlaybackHint()
        controlsHideTask?.cancel()
        controlsHideTask = nil
    }

    func toggleFullScreen() {
        // Native fullscreen uses a normal-level window in its own Space.
        window?.level = .normal
        window?.toggleFullScreen(nil)
    }

    func updateWindowLevel() {
        guard let window else { return }
        window.level = isPinned && !window.styleMask.contains(.fullScreen) ? .floating : .normal
    }

    private func refresh() {
        subtitles.refresh()
        guard player.media != nil else { return }
        if player.state == .error {
            isLoading = false
            isPlaying = false
            errorMessage = L("无法打开或解码此媒体文件，请确认文件完整且可读取。")
            return
        }
        let length = Double(player.media?.length.intValue ?? 0) / 1000
        if length > 0 { duration = length }
        if isLoading && (player.isPlaying || player.state == .paused) {
            isLoading = false
            isPlaying = player.isPlaying
            player.audio?.volume = Int32((volume * 100).rounded())
            player.rate = speed
            showPlaybackHint(.play)
        }
        if pendingResume && duration > 0 && player.isSeekable, let url = currentURL {
            pendingResume = false
            let position = savedPosition(for: url, duration: duration)
            if position > 0 { seek(to: position) }
        }
        let size = player.videoSize
        if videoPresentation == nil && size.width > 0 && size.height > 0 {
            videoPresentation = VideoPresentation(mediaID: loadID, pixels: size)
        }
        let current = Double(player.time.intValue) / 1000
        if isSeeking && (abs(current - elapsed) < 0.5 || (isPlaying && Date().timeIntervalSince(seekRequestedAt) > 3)) {
            isSeeking = false
        }
        if current.isFinite && !isSeeking { elapsed = min(max(current, 0), max(duration, current)) }
        if player.state == .ended {
            elapsed = duration
            isPlaying = false
            hidePlaybackHint()
        }
        if Date().timeIntervalSince(lastPositionSave) >= 5 { savePlaybackPosition() }
    }

    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds.rounded(.down))) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private enum PlaybackError: LocalizedError {
    case unsupported
    var errorDescription: String? { L("当前播放引擎不支持此媒体文件。") }
}

/// Kept with the model so all volume entry points share one persistence policy.
enum InitialVolumeMode: String, CaseIterable, Identifiable {
    case remember, fixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .remember: L("记住上次音量（默认）")
        case .fixed: L("使用固定初始音量")
        }
    }

    static func read(from preferences: UserDefaults) -> Self {
        Self(rawValue: preferences.string(forKey: "initialVolumeMode") ?? "remember") ?? .remember
    }
}

enum VolumePreferences {
    static let defaultVolume = 0.7
    static let lastVolumeKey = "lastPlaybackVolume"
    static let fixedVolumeKey = "fixedInitialVolume"

    static func validated(_ value: Double) -> Double {
        value.isFinite && (0...1).contains(value) ? value : defaultVolume
    }

    static func initialVolume(in preferences: UserDefaults) -> Double {
        let key = InitialVolumeMode.read(from: preferences) == .remember ? lastVolumeKey : fixedVolumeKey
        guard let number = preferences.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return defaultVolume }
        return validated(number.doubleValue)
    }
}
