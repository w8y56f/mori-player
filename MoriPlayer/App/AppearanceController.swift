import AppKit
import Combine
import SwiftUI

/// Resolve System to an explicit color scheme. Passing nil after a forced scheme
/// can leave an NSHostingView's cached appearance unchanged until focus changes.
@MainActor
final class AppearanceController: NSObject, ObservableObject {
    @Published private(set) var selection: AppAppearance
    @Published private(set) var colorScheme: ColorScheme
    private let preferences: UserDefaults
    private let application: NSApplication
    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var systemObservation: NSKeyValueObservation?

    init(preferences: UserDefaults = .standard, application: NSApplication = .shared) {
        self.preferences = preferences
        self.application = application
        let selected = AppAppearance(rawValue: preferences.string(forKey: "appearance") ?? "dark") ?? .dark
        selection = selected
        colorScheme = Self.resolve(selected, systemAppearance: application.effectiveAppearance)
        super.init()
        systemObservation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronize() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: preferences)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func select(_ appearance: AppAppearance) {
        preferences.set(appearance.rawValue, forKey: "appearance")
        synchronize()
    }

    func register(_ window: NSWindow) {
        windows.add(window)
        apply(to: window)
    }

    func apply(to window: NSWindow) {
        let name: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
    }

    private func synchronize() {
        let selected = AppAppearance(rawValue: preferences.string(forKey: "appearance") ?? "dark") ?? .dark
        let resolved = Self.resolve(selected, systemAppearance: application.effectiveAppearance)
        if selection != selected { selection = selected }
        if colorScheme != resolved { colorScheme = resolved }
        for window in windows.allObjects { apply(to: window) }
    }

    private static func resolve(_ selection: AppAppearance, systemAppearance: NSAppearance) -> ColorScheme {
        switch selection {
        case .dark: .dark
        case .light: .light
        case .system: systemAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }
    }

    @objc private func preferencesChanged(_ notification: Notification) { synchronize() }
}

/// Shares the same resolved scheme with native window chrome and SwiftUI content,
/// including the Settings scene whose NSWindow is created by SwiftUI itself.
struct PlayerAppearanceModifier: ViewModifier {
    @ObservedObject var controller: AppearanceController

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, controller.colorScheme)
            .preferredColorScheme(controller.colorScheme)
            .background(AppearanceWindowBridge(controller: controller).frame(width: 0, height: 0))
    }
}

private struct AppearanceWindowBridge: NSViewRepresentable {
    let controller: AppearanceController

    func makeNSView(context: Context) -> AppearanceWindowView {
        let view = AppearanceWindowView()
        view.controller = controller
        return view
    }

    func updateNSView(_ view: AppearanceWindowView, context: Context) {
        if let window = view.window { controller.register(window) }
    }
}

private final class AppearanceWindowView: NSView {
    weak var controller: AppearanceController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { controller?.register(window) }
    }
}
