import AppKit
import AVFoundation
import CoreVideo

@main
struct WindowSizingTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        geometryChecks()
        let suite = "MoriPlayer.SizingTests.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set(false, forKey: "rememberPlaybackPosition")
        prefs.set(true, forKey: "allowMultipleWindows")
        let manager = PlayerWindowCoordinator(preferences: prefs, presentsWindows: false, requestTermination: {})
        let first = manager.ensureWindow()
        let window = first.window!
        let visible = window.screen!.visibleFrame
        let expectedWidth = min(1040, visible.width)
        let initial = window.contentView!.bounds.size
        precondition(abs(initial.width - expectedWidth) < 1)
        if visible.height > 700 { precondition(abs(initial.height - 650) < 1) }
        for _ in 0..<3 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            precondition(window.contentView!.bounds.size == initial, "Hosting layout must not shrink the requested size")
        }
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        let landscape = folder.appendingPathComponent("sizing-landscape.mov")
        let small = folder.appendingPathComponent("sizing-small.mov")
        let rotated = folder.appendingPathComponent("sizing-rotated.mov")
        let large = folder.appendingPathComponent("sizing-4k.mov")
        try await makeVideo(landscape, width: 1280, height: 720)
        try await makeVideo(small, width: 320, height: 180)
        try await makeVideo(rotated, width: 640, height: 360, rotate: true)
        try await makeVideo(large, width: 3840, height: 2160)
        first.player.open(landscape)
        try await ready(first)
        precondition(first.player.videoPresentation!.pixels == CGSize(width: 1280, height: 720))
        precondition(visible.contains(window.frame))
        precondition(first.player.initialVideoPixelLimit == nil)
        let smartSurface = first.player.videoViewport as! PlaybackSurface
        smartSurface.layoutSubtreeIfNeeded()
        precondition(smartSurface.playerView.frame == smartSurface.bounds, "Normal playback must fill its video viewport")
        let smartFrame = window.frame
        first.handleVideoPresentation(.init(mediaID: UUID(), pixels: CGSize(width: 10, height: 10000)))
        precondition(window.frame == smartFrame, "Stale metadata must not resize another file")
        prefs.set("remember", forKey: "initialWindowSizeMode")
        try await Task.sleep(for: .milliseconds(30))
        precondition(window.frame == smartFrame, "Changing the preference must not resize the current video")

        window.setContentSize(CGSize(width: min(1100, visible.width), height: min(700, visible.height - 30)))
        first.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        let manualFrame = window.frame
        let saved = PlayerWindowSizing.rememberedSize(in: prefs)!
        precondition(first.hasUserResized)
        first.player.open(landscape)
        first.player.open(rotated)
        try await ready(first)
        precondition(window.frame == manualFrame)
        smartSurface.layoutSubtreeIfNeeded()
        precondition(smartSurface.playerView.frame == smartSurface.bounds)
        precondition(first.player.videoPresentation!.pixels == CGSize(width: 360, height: 640))

        manager.newWindow()
        let remembered = manager.controllers.last!
        let rememberedContent = remembered.window!.contentView!.bounds.size
        precondition(abs(rememberedContent.width - saved.width) < 1 && abs(rememberedContent.height - saved.height) < 1)
        remembered.player.open(landscape)
        try await ready(remembered)
        precondition(remembered.window!.contentView!.bounds.size == rememberedContent)

        prefs.set("native", forKey: "initialWindowSizeMode")
        manager.newWindow()
        let native = manager.controllers.last!
        native.player.open(small)
        try await ready(native)
        precondition(native.player.initialVideoPixelLimit == CGSize(width: 320, height: 180))
        native.window!.contentView?.layoutSubtreeIfNeeded()
        let surface = native.player.videoViewport as! PlaybackSurface
        surface.layoutSubtreeIfNeeded()
        let nativePoints = native.window!.convertFromBacking(CGRect(x: 0, y: 0, width: 320, height: 180)).size
        precondition(abs(surface.playerView.frame.width - nativePoints.width) < 1)
        precondition(abs(surface.playerView.frame.height - nativePoints.height) < 1)
        native.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        precondition(native.player.initialVideoPixelLimit == nil)
        let nativeManual = native.window!.frame
        native.player.open(large)
        try await ready(native)
        precondition(native.window!.frame == nativeManual)

        manager.newWindow()
        let huge = manager.controllers.last!
        huge.player.open(large)
        try await ready(huge)
        precondition(huge.window!.screen!.visibleFrame.contains(huge.window!.frame))
        prefs.set("smart", forKey: "initialWindowSizeMode")
        manager.newWindow()
        let deferred = manager.controllers.last!
        let beforeDeferred = deferred.window!.frame
        deferred.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification))
        deferred.player.open(rotated)
        try await ready(deferred)
        precondition(deferred.window!.frame == beforeDeferred)
        deferred.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification))
        try await Task.sleep(for: .milliseconds(100))
        precondition(deferred.window!.frame != beforeDeferred, "Deferred sizing must run after exiting fullscreen")

        // Native tab operations can order a surviving tab front. Render no pixels
        // and accept no input while exercising the real group geometry.
        for controller in manager.controllers {
            controller.window!.alphaValue = 0
            controller.window!.ignoresMouseEvents = true
        }
        window.addTabbedWindow(remembered.window!, ordered: .above)
        first.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        precondition(first.hasUserResized && remembered.hasUserResized)
        let groupFrame = remembered.window!.frame
        remembered.player.open(rotated)
        try await ready(remembered)
        precondition(remembered.window!.frame == groupFrame)
        for controller in Array(manager.controllers) { controller.close() }
        print("PASS: stable initial 1040×650 layout, Smart/Remember/Native sizing, real rotated/4K media, pixel-accurate small video, manual override, stale metadata, fullscreen deferral, tab sizing.")
    }

    static func geometryChecks() {
        let visible = CGSize(width: 1600, height: 1000)
        let chrome = CGSize(width: 0, height: 80)
        let minimum = CGSize(width: 800, height: 422)
        let smart = PlayerWindowSizing.fittedVideoFrame(video: CGSize(width: 1920, height: 1080),
            chrome: chrome, visible: visible, minimumFrame: minimum, native: false)
        precondition(smart == CGSize(width: 1200, height: 755))
        let native = PlayerWindowSizing.fittedVideoFrame(video: CGSize(width: 960, height: 540),
            chrome: chrome, visible: visible, minimumFrame: minimum, native: true)
        precondition(native == CGSize(width: 960, height: 620))
        let portrait = PlayerWindowSizing.fittedVideoFrame(video: CGSize(width: 1080, height: 1920),
            chrome: chrome, visible: visible, minimumFrame: minimum, native: false)
        precondition(portrait.width == 800 && portrait.height == 800)
        let external = CGRect(x: -1600, y: 200, width: 1600, height: 1000)
        let frame = PlayerWindowSizing.boundedFrame(size: CGSize(width: 4000, height: 2500),
            topLeft: CGPoint(x: 9000, y: 10000), visible: external)
        precondition(external.contains(frame))
        precondition(!PlayerWindowSizing.isValid(CGSize(width: CGFloat.nan, height: 100)))
    }

    @MainActor
    static func ready(_ controller: PlayerWindowController) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while controller.player.isLoading || controller.player.videoPresentation == nil {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for presentation size")
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(controller.player.canPlay)
        try await Task.sleep(for: .milliseconds(100))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    @MainActor
    static func makeVideo(_ url: URL, width: Int, height: Int, rotate: Bool = false) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        if rotate { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), 0, CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
        precondition(adaptor.append(buffer!, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(seconds: 10, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}
