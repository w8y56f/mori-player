import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// One application process owns independent players and routes every file-open
/// request here. A drop on an existing surface deliberately bypasses routing.
@MainActor
final class PlayerWindowCoordinator: NSObject, ObservableObject {
    @Published private(set) var controllers: [PlayerWindowController] = []
    @Published private(set) var activePlayer: PlayerModel?
    let appearanceController: AppearanceController
    private var lastFocusedID: UUID?
    private let preferences: UserDefaults
    private let presentsWindows: Bool
    private let requestTermination: @MainActor () -> Void

    init(preferences: UserDefaults = .standard, presentsWindows: Bool = true,
         requestTermination: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.preferences = preferences
        appearanceController = AppearanceController(preferences: preferences)
        self.presentsWindows = presentsWindows
        self.requestTermination = requestTermination
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: preferences)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var allowsMultipleWindows: Bool { preferences.bool(forKey: "allowMultipleWindows") }
    var quitsOnLastPlayerClose: Bool {
        preferences.object(forKey: "quitOnLastPlayerClose") as? Bool ?? true
    }

    @discardableResult
    func ensureWindow() -> PlayerWindowController {
        let controller = preferredController ?? makeWindow()
        present(controller)
        return controller
    }

    func newWindow() {
        guard allowsMultipleWindows else { return }
        present(makeWindow())
    }

    func openFile(from source: PlayerWindowController? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audio] + ["avi", "wmv", "rm", "rmvb", "mkv"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = L("打开")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURLs([url], from: source)
    }

    func openURLs(_ urls: [URL], from source: PlayerWindowController? = nil) {
        let files = urls.filter(\.isFileURL)
        let requested = allowsMultipleWindows ? files : Array(files.prefix(1))
        for url in requested {
            let target: PlayerWindowController
            if allowsMultipleWindows {
                let emptySource = source.flatMap { $0.player.fileName == nil ? $0 : nil }
                let emptyPreferred = preferredController.flatMap { $0.player.fileName == nil ? $0 : nil }
                target = emptySource ?? emptyPreferred ?? makeWindow()
            } else {
                target = source ?? preferredController ?? makeWindow()
            }
            target.player.open(url)
            present(target)
        }
    }

    func didFocus(_ controller: PlayerWindowController) {
        lastFocusedID = controller.id
        activePlayer = controller.player
    }

    func didResignFocus(_ controller: PlayerWindowController) {
        if activePlayer === controller.player { activePlayer = nil }
    }

    func didClose(_ controller: PlayerWindowController) {
        guard controllers.contains(where: { $0 === controller }) else { return }
        // AppKit may still be updating a tab group inside its close notification.
        // Retain the controller until that stack has unwound, then release its host.
        DispatchQueue.main.async { [controller] in withExtendedLifetime(controller) {} }
        controller.stopObservingPlayer()
        controller.player.closePlayback()
        if activePlayer === controller.player { activePlayer = nil }
        controllers.removeAll { $0.id == controller.id }
        if lastFocusedID == controller.id { lastFocusedID = controllers.last?.id }
        if controllers.isEmpty {
            // Finish AppKit's tab/window close stack and player cleanup before
            // terminating. Settings is deliberately not counted as a player.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.controllers.isEmpty, self.quitsOnLastPlayerClose else { return }
                self.requestTermination()
            }
        }
    }

    func saveAllPositions() {
        for controller in controllers { controller.player.savePlaybackPosition() }
    }

    private var preferredController: PlayerWindowController? {
        controllers.first { $0.player === activePlayer } ??
            controllers.first { $0.id == lastFocusedID } ?? controllers.last
    }

    func sizingPeers(of controller: PlayerWindowController) -> [PlayerWindowController] {
        guard let tabs = controller.window?.tabbedWindows, tabs.count > 1 else { return [controller] }
        return controllers.filter { candidate in tabs.contains { $0 === candidate.window } }
    }

    func recordManualResize(of controller: PlayerWindowController) {
        guard let window = controller.window, !window.styleMask.contains(.fullScreen) else { return }
        for peer in sizingPeers(of: controller) { peer.markManuallySized() }
        if let size = window.contentView?.bounds.size { PlayerWindowSizing.saveContentSize(size, in: preferences) }
    }

    private func makeWindow() -> PlayerWindowController {
        let controller = PlayerWindowController(coordinator: self, preferences: preferences,
            initialScreen: preferredController?.window?.screen ?? NSScreen.main)
        controllers.append(controller)
        return controller
    }

    private func present(_ controller: PlayerWindowController) {
        // The test harness creates undisplayed windows and never changes desktop focus.
        guard presentsWindows else { return }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func preferencesChanged(_ notification: Notification) {
        objectWillChange.send()
    }
}

@MainActor
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    let id = UUID()
    let player: PlayerModel
    private weak var coordinator: PlayerWindowCoordinator?
    private let preferences: UserDefaults
    private var observations = Set<AnyCancellable>()
    private(set) var hasUserResized = false
    private var pendingMode: InitialWindowSizeMode = .smart
    private var pendingPresentation: PlayerModel.VideoPresentation?
    private var handledMediaID: UUID?
    private var isApplyingFrame = false
    private var isFullScreenTransition = false

    init(coordinator: PlayerWindowCoordinator, preferences: UserDefaults, initialScreen: NSScreen? = nil) {
        self.coordinator = coordinator
        self.preferences = preferences
        player = PlayerModel(preferences: preferences)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Mori Player"
        window.identifier = NSUserInterfaceItemIdentifier("player.\(id.uuidString)")
        window.contentMinSize = NSSize(width: 800, height: 400)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        player.window = window
        let hosting = NSHostingController(rootView: PlayerWindowRoot(
            model: player, appearanceController: coordinator.appearanceController, onOpenFile: { [weak self, weak coordinator] in
                coordinator?.openFile(from: self)
            }))
        // The native window owns sizing. The hosting layer must not replace the
        // requested content size with its intrinsic/minimum SwiftUI fitting size.
        hosting.sizingOptions = []
        (hosting.view as? NSHostingView<PlayerWindowRoot>)?.sizingOptions = []
        window.contentViewController = hosting
        configureInitialSize(on: initialScreen)
        updateAppearance()
        player.$fileName.sink { [weak self, weak window] name in
            window?.title = name ?? "Mori Player"
            if name != nil {
                self?.pendingMode = InitialWindowSizeMode.read(from: preferences)
                self?.handledMediaID = nil
                self?.pendingPresentation = nil
            }
        }
            .store(in: &observations)
        player.$videoPresentation.sink { [weak self] presentation in
            guard let presentation else { return }
            DispatchQueue.main.async { [weak self] in self?.handleVideoPresentation(presentation) }
        }.store(in: &observations)
        player.objectWillChange.sink { [weak coordinator] in coordinator?.objectWillChange.send() }
            .store(in: &observations)
    }

    required init?(coder: NSCoder) { nil }

    func stopObservingPlayer() { observations.removeAll() }

    func updateAppearance() {
        if let window { coordinator?.appearanceController.register(window) }
    }

    private var visibleFrame: CGRect {
        (window?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var decorationSize: CGSize {
        guard let window else { return .zero }
        let content = window.contentView?.bounds.size ?? window.contentRect(forFrameRect: window.frame).size
        return CGSize(width: max(0, window.frame.width - content.width), height: max(0, window.frame.height - content.height))
    }

    private func minimumFrameSize(in visible: CGRect) -> CGSize {
        let decoration = decorationSize
        return CGSize(width: min(800 + decoration.width, visible.width),
                      height: min(400 + decoration.height, visible.height))
    }

    private func configureInitialSize(on screen: NSScreen?) {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = screen?.visibleFrame ?? visibleFrame
        let content = InitialWindowSizeMode.read(from: preferences) == .remember
            ? PlayerWindowSizing.rememberedSize(in: preferences) ?? PlayerWindowSizing.defaultContentSize
            : PlayerWindowSizing.defaultContentSize
        let decoration = decorationSize
        let size = PlayerWindowSizing.constrain(CGSize(width: content.width + decoration.width,
            height: content.height + decoration.height), minimum: minimumFrameSize(in: visible), maximum: visible.size)
        let centerTop = CGPoint(x: visible.midX - size.width / 2, y: visible.midY + size.height / 2)
        applyFrame(size: size, topLeft: centerTop, visible: visible)
    }

    private func applyFrame(size: CGSize, topLeft: CGPoint, visible: CGRect) {
        guard let window else { return }
        isApplyingFrame = true
        defer { isApplyingFrame = false }
        let decoration = decorationSize
        window.contentMinSize = CGSize(width: min(800, max(1, visible.width - decoration.width)),
                                       height: min(400, max(1, visible.height - decoration.height)))
        window.setFrame(PlayerWindowSizing.boundedFrame(size: size, topLeft: topLeft, visible: visible), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func markManuallySized() {
        hasUserResized = true
        pendingPresentation = nil
        player.initialVideoPixelLimit = nil
    }

    func handleVideoPresentation(_ presentation: PlayerModel.VideoPresentation) {
        guard presentation.mediaID == player.currentMediaID,
              handledMediaID != presentation.mediaID, PlayerWindowSizing.isValid(presentation.pixels) else { return }
        pendingPresentation = presentation
        applyPendingVideoSize()
    }

    private func applyPendingVideoSize() {
        guard let window, let presentation = pendingPresentation,
              presentation.mediaID == player.currentMediaID,
              !window.styleMask.contains(.fullScreen), !isFullScreenTransition else { return }
        let peers = coordinator?.sizingPeers(of: self) ?? [self]
        if peers.count > 1 || hasUserResized {
            if peers.contains(where: \.hasUserResized) { hasUserResized = true }
            handledMediaID = presentation.mediaID
            pendingPresentation = nil
            return
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = visibleFrame
        let decoration = decorationSize
        let target: CGSize
        switch pendingMode {
        case .remember:
            let content = PlayerWindowSizing.rememberedSize(in: preferences) ?? PlayerWindowSizing.defaultContentSize
            target = PlayerWindowSizing.constrain(CGSize(width: content.width + decoration.width,
                height: content.height + decoration.height), minimum: minimumFrameSize(in: visible), maximum: visible.size)
        case .smart, .native:
            let video = pendingMode == .native
                ? window.convertFromBacking(CGRect(origin: .zero, size: presentation.pixels)).size
                : presentation.pixels
            let viewport = player.videoViewport?.bounds.size ?? .zero
            let chrome = CGSize(width: viewport.width > 0 ? max(0, window.frame.width - viewport.width) : decoration.width,
                                height: viewport.height > 0 ? max(0, window.frame.height - viewport.height) : decoration.height + 60)
            target = PlayerWindowSizing.fittedVideoFrame(video: video, chrome: chrome, visible: visible.size,
                minimumFrame: minimumFrameSize(in: visible), native: pendingMode == .native)
        }
        player.initialVideoPixelLimit = pendingMode == .native ? presentation.pixels : nil
        handledMediaID = presentation.mediaID
        pendingPresentation = nil
        applyFrame(size: target, topLeft: CGPoint(x: window.frame.minX, y: window.frame.maxY), visible: visible)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !isApplyingFrame, !isFullScreenTransition else { return }
        coordinator?.recordManualResize(of: self)
    }

    func windowWillEnterFullScreen(_ notification: Notification) { isFullScreenTransition = true }
    func windowDidEnterFullScreen(_ notification: Notification) { isFullScreenTransition = false }
    func windowWillExitFullScreen(_ notification: Notification) { isFullScreenTransition = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        isFullScreenTransition = false
        DispatchQueue.main.async { [weak self] in self?.applyPendingVideoSize() }
    }

    func windowDidBecomeKey(_ notification: Notification) { coordinator?.didFocus(self) }
    func windowDidResignKey(_ notification: Notification) { coordinator?.didResignFocus(self) }
    func windowWillClose(_ notification: Notification) { coordinator?.didClose(self) }
}

private struct PlayerWindowRoot: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @ObservedObject var model: PlayerModel
    let appearanceController: AppearanceController
    let onOpenFile: () -> Void

    var body: some View {
        PlayerWindowView(model: model, onOpenFile: onOpenFile)
            .modifier(PlayerAppearanceModifier(controller: appearanceController))
    }
}
