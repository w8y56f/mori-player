import SwiftUI
import AVKit

struct PlayerSurface: NSViewRepresentable {
    @ObservedObject var model: PlayerModel

    func makeNSView(context: Context) -> PlaybackSurface {
        let view = PlaybackSurface()
        view.model = model
        view.player = model.player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: PlaybackSurface, context: Context) {}

    static func dismantleNSView(_ view: PlaybackSurface, coordinator: ()) {
        view.shutdown()
    }
}

final class PlaybackSurface: AVPlayerView {
    weak var model: PlayerModel?
    private var eventMonitor: Any?
    private var clickTask: Task<Void, Never>?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        guard let window else { return }
        model?.window = window
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  !(self.window?.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 49: self.model?.togglePlayback()
            case 123: self.model?.seek(by: -5)
            case 124: self.model?.seek(by: 5)
            case 125: self.model?.changeVolume(by: -0.05)
            case 126: self.model?.changeVolume(by: 0.05)
            case 53:
                guard self.window?.styleMask.contains(.fullScreen) == true else { return event }
                self.model?.toggleFullScreen()
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a": self.model?.changeSpeed(by: 0.25)
                case "s": self.model?.changeSpeed(by: -0.25)
                default: return event
                }
            }
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        clickTask?.cancel()
        if event.clickCount == 2 {
            model?.toggleFullScreen()
        } else if event.clickCount == 1 {
            clickTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled else { return }
                self?.model?.togglePlayback()
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.phase != .ended, event.momentumPhase == [] else { return }
        // Positive vertical wheel motion raises volume, independent of natural scrolling.
        let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard delta != 0 else { return }
        let step = event.hasPreciseScrollingDeltas ? min(abs(delta) * 0.002, 0.05) : 0.05
        model?.changeVolume(by: delta > 0 ? step : -step)
    }

    func shutdown() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        clickTask?.cancel()
    }
}
