import AppKit

/// Checks event routing without sending input to the user's desktop.
@main
struct PlayerInteractionTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let surface = PlaybackSurface(frame: NSRect(x: 20, y: 40, width: 400, height: 300))
        let model = PlayerModel()
        surface.model = model
        host.addSubview(surface)
        host.layoutSubtreeIfNeeded()
        // AVPlayerView's internal views must never steal input from the surface.
        precondition(host.hitTest(NSPoint(x: 220, y: 190)) === surface)
        precondition(surface.hitTest(NSPoint(x: 0, y: 0)) == nil)
        precondition(surface.registeredDraggedTypes.contains(.fileURL))
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = host
        precondition(model.window === window)
        model.isPinned = true
        precondition(window.level == .floating)
        model.isPinned = false
        precondition(window.level == .normal)
        surface.shutdown()
        try await presentationChecks()
        gestureChecks()
        seekAndScrollChecks()
        print("PASS: mouse events reach the playback surface, outside clicks pass through, file drops registered, pin toggles window level, presentation timers, activation/click/drag arbitration, seek mapping and scroll direction.")
    }

    @MainActor
    static func presentationChecks() async throws {
        let model = PlayerModel()
        precondition(!model.isSpeedVisible)
        model.changeSpeed(by: 0.25)
        precondition(model.isSpeedVisible)
        try await Task.sleep(for: .milliseconds(650))
        model.changeSpeed(by: -0.25)
        precondition(model.speed == 1 && model.isSpeedVisible)
        try await Task.sleep(for: .milliseconds(650))
        precondition(model.isSpeedVisible, "An old timer must not hide a renewed hint")
        try await Task.sleep(for: .milliseconds(500))
        precondition(!model.isSpeedVisible)
        model.changeSpeed(by: 100)
        model.changeSpeed(by: 0.25)
        precondition(model.speed == 4 && model.isSpeedVisible)
        model.hideSpeedHint()
        precondition(!model.isSpeedVisible)

        model.setFullScreen(true)
        precondition(!model.areControlsVisible)
        model.pointerMoved()
        precondition(model.areControlsVisible)
        try await Task.sleep(for: .milliseconds(1200))
        model.pointerMoved()
        try await Task.sleep(for: .milliseconds(1100))
        precondition(model.areControlsVisible, "Mouse motion must restart the hide timer")
        try await Task.sleep(for: .milliseconds(1100))
        precondition(!model.areControlsVisible)

        model.pointerMoved()
        model.setControlsHovered(true)
        try await Task.sleep(for: .milliseconds(2200))
        precondition(model.areControlsVisible, "Hover must prevent hiding")
        model.setControlsInteracting(true)
        model.setControlsHovered(false)
        try await Task.sleep(for: .milliseconds(2200))
        precondition(model.areControlsVisible, "Dragging outside the bar must prevent hiding")
        model.setControlsInteracting(false)
        try await Task.sleep(for: .milliseconds(2200))
        precondition(!model.areControlsVisible)

        model.pointerMoved()
        model.setFullScreen(false)
        try await Task.sleep(for: .milliseconds(2200))
        precondition(model.areControlsVisible, "An old fullscreen timer must not hide window controls")
        model.changeSpeed(by: -0.25)
        model.cancelPresentationTasks()
        precondition(!model.isSpeedVisible)
    }

    @MainActor
    static func gestureChecks() {
        var gesture = PlaybackPointerGesture()
        let point = NSPoint(x: 100, y: 100)
        // An activation click must not count towards a later double-click.
        gesture.begin(at: point, timestamp: 0, clickCount: 1, activationOnly: true, canDrag: true)
        precondition(!gesture.beginDragIfNeeded(at: NSPoint(x: 103, y: 100)))
        precondition(gesture.finish(timestamp: 0.05) == .none)
        gesture.begin(at: point, timestamp: 0.1, clickCount: 2, activationOnly: false, canDrag: true)
        precondition(gesture.finish(timestamp: 0.15) == .click)
        gesture.reset()
        gesture.begin(at: point, timestamp: 1, clickCount: 1, activationOnly: false, canDrag: true)
        precondition(!gesture.beginDragIfNeeded(at: NSPoint(x: 103, y: 100)))
        precondition(gesture.finish(timestamp: 1.05) == .click)
        gesture.begin(at: point, timestamp: 1.06, clickCount: 2, activationOnly: false, canDrag: true)
        precondition(gesture.finish(timestamp: 1.1) == .doubleClick)
        gesture.begin(at: point, timestamp: 2, clickCount: 1, activationOnly: false, canDrag: true)
        precondition(gesture.beginDragIfNeeded(at: NSPoint(x: 105, y: 100)))
        precondition(!gesture.beginDragIfNeeded(at: NSPoint(x: 110, y: 100)))
        precondition(gesture.finish(timestamp: 3) == .none)
        // A hold without movement remains a click on release, never on press.
        gesture.begin(at: point, timestamp: 4, clickCount: 1, activationOnly: false, canDrag: true)
        precondition(gesture.finish(timestamp: 6) == .click)
        gesture.begin(at: point, timestamp: 7, clickCount: 1, activationOnly: false, canDrag: false)
        precondition(!gesture.beginDragIfNeeded(at: NSPoint(x: 120, y: 100)))
        gesture.reset()
        precondition(gesture.finish(timestamp: 8) == .none)

        // Both active and activation-only presses may become window drags.
        // Drag release never toggles playback and cannot seed a double-click.
        for activationOnly in [false, true] {
            gesture.reset()
            gesture.begin(at: point, timestamp: 10, clickCount: 1,
                          activationOnly: activationOnly, canDrag: true)
            precondition(gesture.beginDragIfNeeded(at: NSPoint(x: 105, y: 100)))
            precondition(gesture.finish(timestamp: 10.05) == .none)
            gesture.begin(at: point, timestamp: 10.1, clickCount: 2,
                          activationOnly: false, canDrag: true)
            precondition(gesture.finish(timestamp: 10.15) == .click)
        }
        // Fullscreen / nonmovable windows must not start a drag, even when inactive.
        gesture.begin(at: point, timestamp: 11, clickCount: 1,
                      activationOnly: true, canDrag: false)
        precondition(!gesture.beginDragIfNeeded(at: NSPoint(x: 120, y: 100)))
        precondition(gesture.finish(timestamp: 11.1) == .none)
    }

    @MainActor
    static func seekAndScrollChecks() {
        precondition(SeekBarGeometry.time(at: 8, duration: 100, width: 216) == 0)
        precondition(SeekBarGeometry.time(at: 108, duration: 100, width: 216) == 50)
        precondition(SeekBarGeometry.time(at: 208, duration: 100, width: 216) == 100)
        precondition(SeekBarGeometry.time(at: -100, duration: 100, width: 216) == 0)
        precondition(SeekBarGeometry.time(at: 500, duration: 100, width: 216) == 100)
        precondition(SeekBarGeometry.time(at: 100, duration: 0, width: 216) == 0)
        precondition(SeekBarGeometry.time(at: 100, duration: .nan, width: 216) == 0)
        for time in [0.0, 25, 50, 100] {
            let x = SeekBarGeometry.position(for: time, duration: 100, width: 216)
            precondition(abs(SeekBarGeometry.time(at: x, duration: 100, width: 216) - time) < 0.001)
        }
        precondition(PlaybackSurface.volumeChange(delta: 1, invertedBySystem: false, precise: false, reverse: true) == -0.05)
        precondition(PlaybackSurface.volumeChange(delta: 1, invertedBySystem: false, precise: false, reverse: false) == 0.05)
        precondition(PlaybackSurface.volumeChange(delta: -1, invertedBySystem: false, precise: false, reverse: true) == 0.05)
        precondition(PlaybackSurface.volumeChange(delta: -1, invertedBySystem: true, precise: false, reverse: true) == -0.05)
        precondition(PlaybackSurface.volumeChange(delta: 0, invertedBySystem: false, precise: true, reverse: true) == 0)
        precondition(PlaybackSurface.volumeChange(delta: 100, invertedBySystem: false, precise: true, reverse: true) == -0.05)
    }

}
