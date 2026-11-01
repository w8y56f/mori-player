import SwiftUI
import VLCKit

struct PlayerSurface: NSViewRepresentable {
    @ObservedObject var model: PlayerModel

    func makeNSView(context: Context) -> PlaybackSurface {
        let view = PlaybackSurface()
        view.model = model
        model.player.drawable = view.playerView
        view.playerView.isHidden = !model.canPlay
        model.videoViewport = view
        return view
    }

    func updateNSView(_ view: PlaybackSurface, context: Context) {
        view.playerView.isHidden = !model.canPlay
        view.maximumPixelSize = model.isFullScreen ? nil : model.initialVideoPixelLimit
    }

    static func dismantleNSView(_ view: PlaybackSurface, coordinator: ()) {
        view.shutdown()
    }
}

/// Owns input independently of AVPlayerView's private child views, which can
/// consume clicks before an AVPlayerView subclass receives mouseDown.
final class PlaybackSurface: NSView {
    let playerView = SubtitleDropVideoView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerView.dropOwner = self
        playerView.fillScreen = false
        addSubview(playerView)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    var maximumPixelSize: CGSize? { didSet { if oldValue != maximumPixelSize { needsLayout = true } } }

    override func layout() {
        super.layout()
        guard let pixels = maximumPixelSize, pixels.width > 0, pixels.height > 0 else {
            playerView.frame = bounds
            return
        }
        let points = convertFromBacking(CGRect(origin: .zero, size: pixels)).size
        let scale = min(1, bounds.width / points.width, bounds.height / points.height)
        let size = CGSize(width: points.width * scale, height: points.height * scale)
        playerView.frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // hitTest receives coordinates in the superview's coordinate system.
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    private var activationOnlyClick = false
    private var gesture = PlaybackPointerGesture()
    private var mouseDownEvent: NSEvent?
    private weak var trackedWindow: NSWindow?
    private var previousAcceptsMouseMovedEvents = false
    private var isShutDown = false

    private var activateOnFirstClick: Bool {
        UserDefaults.standard.object(forKey: "activateOnFirstClick") as? Bool ?? true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // AppKit asks this before activating an inactive window. Keep that fact
        // through mouseDown, by which time isKeyWindow may already be true.
        activationOnlyClick = activateOnFirstClick
        return true
    }

    weak var model: PlayerModel?
    private var eventMonitor: Any?
    private var clickTask: Task<Void, Never>?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        NotificationCenter.default.removeObserver(self)
        trackedWindow?.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        trackedWindow = nil
        clickTask?.cancel()
        gesture.reset()
        guard !isShutDown, let window else { return }
        model?.window = window
        trackedWindow = window
        previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        model?.setFullScreen(window.styleMask.contains(.fullScreen))
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                               name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(fullScreenDidChange),
                                               name: NSWindow.didExitFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(fullScreenDidChange),
                                               name: NSWindow.didEnterFullScreenNotification, object: window)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type != .keyDown {
                if event.type == .mouseMoved || event.type == .leftMouseDragged {
                    self.model?.pointerMoved()
                }
                if event.type == .leftMouseDown {
                    let point = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(point), self.activateOnFirstClick,
                       !NSApp.isActive || self.window?.isKeyWindow != true {
                        self.activationOnlyClick = true
                    }
                }
                // Release also covers a button press that ends outside the bar.
                if event.type == .leftMouseUp { self.model?.setControlsInteracting(false) }
                return event
            }
            guard !(self.window?.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 49: self.model?.togglePlayback()
            case 123: self.model?.skip(forward: false)
            case 124: self.model?.skip(forward: true)
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

    @objc private func fullScreenDidChange(_ notification: Notification) {
        model?.setFullScreen(window?.styleMask.contains(.fullScreen) == true)
        model?.updateWindowLevel()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        clickTask?.cancel()
        gesture.reset()
        mouseDownEvent = nil
        model?.setControlsInteracting(false)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // The window controller owns playback lifecycle and persistence.
        shutdown()
    }

    private func droppedURL(from sender: NSDraggingInfo) -> URL? {
        guard sender.draggingSourceOperationMask.contains(.copy),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL],
              urls.count == 1, let url = urls.first, !url.hasDirectoryPath else { return nil }
        return url
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = droppedURL(from: sender) != nil
        layer?.borderWidth = accepts ? 3 : 0
        return accepts ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        guard let url = droppedURL(from: sender), let model else { return false }
        clickTask?.cancel()
        if SubtitleFiles.accepts(url) { model.subtitles.load(url) } else { model.open(url) }
        window?.makeFirstResponder(self)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { layer?.borderWidth = 0 }

    override func mouseDown(with event: NSEvent) {
        clickTask?.cancel()
        let activationOnly = activationOnlyClick ||
            (activateOnFirstClick && (!NSApp.isActive || window?.isKeyWindow != true))
        activationOnlyClick = false
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        mouseDownEvent = event
        gesture.begin(at: event.locationInWindow, timestamp: event.timestamp,
                      clickCount: event.clickCount, activationOnly: activationOnly,
                      canDrag: window.map { $0.isMovable && !$0.styleMask.contains(.fullScreen) } ?? false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard gesture.beginDragIfNeeded(at: event.locationInWindow), let mouseDownEvent else { return }
        clickTask?.cancel()
        window?.performDrag(with: mouseDownEvent)
        // performDrag runs its own tracking loop and may consume mouseUp.
        gesture.reset()
        self.mouseDownEvent = nil
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        switch gesture.finish(timestamp: event.timestamp) {
        case .none: break
        case .doubleClick:
            clickTask?.cancel()
            model?.toggleFullScreen()
        case .click:
            let item = model?.player.media
            clickTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
                guard let self, let item, self.model?.player.media === item else { return }
                self.model?.togglePlayback()
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.phase != .ended, event.momentumPhase == [] else { return }
        let reverse = UserDefaults.standard.object(forKey: "reverseVolumeScroll") as? Bool ?? true
        model?.changeVolume(by: Self.volumeChange(delta: event.scrollingDeltaY,
            invertedBySystem: event.isDirectionInvertedFromDevice,
            precise: event.hasPreciseScrollingDeltas, reverse: reverse))
    }


    static func volumeChange(delta: Double, invertedBySystem: Bool, precise: Bool, reverse: Bool) -> Double {
        let physicalDelta = delta * (invertedBySystem ? -1 : 1)
        guard physicalDelta != 0 else { return 0 }
        let step = precise ? min(abs(physicalDelta) * 0.002, 0.05) : 0.05
        return step * (physicalDelta > 0 ? 1 : -1) * (reverse ? -1 : 1)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        clickTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        trackedWindow?.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        trackedWindow = nil
        gesture.reset()
        // dismantleNSView is also called while SwiftUI destroys its graph.
        // Never publish model changes here: that re-enters graph destruction.
        model?.player.drawable = nil
        model = nil
    }
}

/// Separates activation, click, double-click, and drag without a desktop event loop.
struct PlaybackPointerGesture {
    enum ReleaseAction { case none, click, doubleClick }
    private var origin: NSPoint?
    private var activationOnly = false
    private var canDrag = false
    private var dragged = false
    private var isDoubleClick = false
    private var lastClick: (point: NSPoint, timestamp: TimeInterval)?

    mutating func begin(at point: NSPoint, timestamp: TimeInterval, clickCount: Int,
                        activationOnly: Bool, canDrag: Bool) {
        origin = point
        self.activationOnly = activationOnly
        self.canDrag = canDrag
        dragged = false
        isDoubleClick = !activationOnly && clickCount == 2 && lastClick.map {
            timestamp - $0.timestamp <= NSEvent.doubleClickInterval &&
                hypot(point.x - $0.point.x, point.y - $0.point.y) <= 4
        } == true
        if activationOnly { lastClick = nil }
    }

    mutating func beginDragIfNeeded(at point: NSPoint) -> Bool {
        // Activation-only applies to a click, not a title-bar-style window drag.
        guard let origin, canDrag, !dragged,
              hypot(point.x - origin.x, point.y - origin.y) > 4 else { return false }
        dragged = true
        lastClick = nil
        return true
    }

    mutating func finish(timestamp: TimeInterval) -> ReleaseAction {
        guard let origin else { return .none }
        self.origin = nil
        guard !activationOnly, !dragged else { return .none }
        if isDoubleClick {
            lastClick = nil
            return .doubleClick
        }
        lastClick = (origin, timestamp)
        return .click
    }

    mutating func reset() {
        origin = nil
        lastClick = nil
    }
}

/// VLC's drawable is itself a native drag destination. Forward file drops to the
/// same owner as pointer gestures rather than letting the renderer consume them.
final class SubtitleDropVideoView: VLCVideoView {
    weak var dropOwner: PlaybackSurface?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOwner?.draggingEntered(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOwner?.draggingUpdated(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropOwner?.draggingExited(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropOwner?.prepareForDragOperation(sender) ?? false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropOwner?.performDragOperation(sender) ?? false }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { dropOwner?.concludeDragOperation(sender) }
}
