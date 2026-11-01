import AppKit
import SwiftUI

@MainActor
private final class SchemeRecorder {
    var scheme: ColorScheme?
}

private struct SchemeProbe: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let recorder: SchemeRecorder

    func makeNSView(context: Context) -> NSView {
        recorder.scheme = colorScheme
        return NSView()
    }

    func updateNSView(_ view: NSView, context: Context) { recorder.scheme = colorScheme }
}

/// Only this test process's application appearance is simulated. No system
/// preference is changed, and none of these windows are shown or activated.
@main
struct AppearanceTests {
    @MainActor
    static func main() async throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        defer { app.appearance = previousAppearance }
        app.appearance = NSAppearance(named: .aqua)
        let suite = "MoriPlayer.AppearanceTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let coordinator = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false, requestTermination: {})
        preferences.set(true, forKey: "allowMultipleWindows")
        coordinator.ensureWindow()
        coordinator.newWindow()
        let theme = coordinator.appearanceController
        precondition(theme.selection == .dark && theme.colorScheme == .dark)

        // The same modifier used by the player and Settings must update actual
        // SwiftUI environment values as well as each native hosting window.
        let recorders = [SchemeRecorder(), SchemeRecorder()]
        let probeWindows = recorders.map { recorder in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView:
                SchemeProbe(recorder: recorder).frame(width: 200, height: 100)
                    .modifier(PlayerAppearanceModifier(controller: theme)))
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        let allWindows = coordinator.controllers.compactMap(\.window) + probeWindows
        try await check(.dark, theme: theme, windows: allWindows, recorders: recorders)
        for _ in 0..<3 {
            theme.select(.system)
            precondition(theme.colorScheme == .light, "System must resolve immediately, without a focus event")
            try await check(.light, theme: theme, windows: allWindows, recorders: recorders)
            theme.select(.dark)
            try await check(.dark, theme: theme, windows: allWindows, recorders: recorders)
            theme.select(.light)
            try await check(.light, theme: theme, windows: allWindows, recorders: recorders)
            theme.select(.dark)
            try await check(.dark, theme: theme, windows: allWindows, recorders: recorders)
        }
        theme.select(.system)
        app.appearance = NSAppearance(named: .darkAqua)
        try await check(.dark, theme: theme, windows: allWindows, recorders: recorders)
        app.appearance = NSAppearance(named: .aqua)
        try await check(.light, theme: theme, windows: allWindows, recorders: recorders)
        theme.select(.light)
        app.appearance = NSAppearance(named: .darkAqua)
        try await check(.light, theme: theme, windows: allWindows, recorders: recorders)
        theme.select(.system)
        try await check(.dark, theme: theme, windows: allWindows, recorders: recorders)
        let restored = AppearanceController(preferences: preferences)
        precondition(restored.selection == .system && restored.colorScheme == .dark)
        for controller in Array(coordinator.controllers) { controller.close() }
        for window in probeWindows { window.close() }
        print("PASS: Dark → System on light appearance without focus changes, repeated switches, native chrome/content synchronization, system changes, forced override, saved selection.")
    }

    @MainActor
    private static func check(_ expected: ColorScheme, theme: AppearanceController,
                      windows: [NSWindow], recorders: [SchemeRecorder]) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        let name: NSAppearance.Name = expected == .dark ? .darkAqua : .aqua
        while true {
            for window in windows { window.contentView?.layoutSubtreeIfNeeded() }
            let matches = theme.colorScheme == expected && recorders.allSatisfy { $0.scheme == expected } &&
                windows.allSatisfy { $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name &&
                    $0.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name }
            if matches { break }
            precondition(ContinuousClock.now < deadline, "Window and SwiftUI content did not update without a focus change")
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(windows.allSatisfy { !$0.isVisible }, "Appearance tests must not show windows")
    }
}
