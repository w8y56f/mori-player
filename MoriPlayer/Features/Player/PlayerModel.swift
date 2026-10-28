import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var fileName: String?
    @Published var elapsed = 0.0
    @Published var duration = 0.0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var speed: Float = 1
    @Published var volume: Double = 0.7 {
        didSet { player.volume = Float(volume) }
    }
    @Published var errorMessage: String?
    weak var window: NSWindow?
    private var polling: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var scopedURL: URL?
    private var loadID = UUID()
    private var seekID = UUID()
    private var isSeeking = false

    init() {
        player.volume = Float(volume)
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
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    var canPlay: Bool { player.currentItem != nil && !isLoading }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        loading?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
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
        loading = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let time = try await asset.load(.duration)
                guard let self, self.loadID == id, !Task.isCancelled else { return }
                guard playable, time.seconds.isFinite, time.seconds > 0 else {
                    throw PlaybackError.unsupported
                }
                self.duration = time.seconds
                self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                self.isLoading = false
                self.player.playImmediately(atRate: self.speed)
                self.isPlaying = true
            } catch {
                guard let self, self.loadID == id, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = "无法播放此文件。请确认文件完整，并使用 macOS 支持的媒体格式。\n\(error.localizedDescription)"
            }
        }
    }

    func togglePlayback() {
        guard canPlay else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if elapsed >= duration - 0.1 { seek(to: 0) }
            player.playImmediately(atRate: speed)
            isPlaying = true
        }
    }

    func stop() {
        guard canPlay else { return }
        player.pause()
        isPlaying = false
        seek(to: 0)
    }

    func seek(by seconds: Double) { seek(to: elapsed + seconds) }

    func seek(to seconds: Double) {
        guard canPlay else { return }
        let target = min(max(seconds, 0), duration)
        let id = UUID()
        seekID = id
        isSeeking = true
        elapsed = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.seekID == id else { return }
                self.isSeeking = false
            }
        }
    }

    func changeVolume(by delta: Double) { volume = min(max(volume + delta, 0), 1) }

    func changeSpeed(by delta: Float) {
        speed = min(max(speed + delta, 0.25), 4)
        if isPlaying { player.playImmediately(atRate: speed) }
    }

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    private func refresh() {
        guard canPlay else { return }
        if player.currentItem?.status == .failed {
            errorMessage = player.currentItem?.error?.localizedDescription ?? "播放失败，请尝试其他媒体文件。"
            player.pause()
            isPlaying = false
            player.replaceCurrentItem(with: nil)
            return
        }
        let current = player.currentTime().seconds
        if current.isFinite && !isSeeking { elapsed = min(max(current, 0), duration) }
        if player.rate == 0 && elapsed >= duration - 0.1 { isPlaying = false }
    }

    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds.rounded(.down))) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private enum PlaybackError: LocalizedError {
    case unsupported
    var errorDescription: String? { "当前播放引擎不支持此媒体文件。" }
}
