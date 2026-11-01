import AppKit

/// Termination is injected as a counter: no application is actually quit.
@main
struct WindowClosePolicyTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let suite = "MoriPlayer.ClosePolicyTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var quitCount = 0
        let manager = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false,
                                             requestTermination: { quitCount += 1 })
        precondition(manager.quitsOnLastPlayerClose)
        // An open Settings/other native window must not prevent the final player
        // from triggering termination; closing that other window must not quit.
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        manager.ensureWindow().close()
        precondition(quitCount == 0, "Do not terminate from inside AppKit's close callback")
        try await settle()
        precondition(quitCount == 1)

        preferences.set(false, forKey: "quitOnLastPlayerClose")
        manager.ensureWindow().close()
        try await settle()
        precondition(quitCount == 1 && manager.controllers.isEmpty)
        let reopened = manager.ensureWindow()
        precondition(manager.controllers.count == 1)
        settings.close()
        try await settle()
        precondition(quitCount == 1 && manager.controllers.count == 1)

        preferences.set(true, forKey: "quitOnLastPlayerClose")
        preferences.set(true, forKey: "allowMultipleWindows")
        manager.newWindow()
        reopened.close()
        try await settle()
        precondition(quitCount == 1 && manager.controllers.count == 1)
        manager.controllers[0].close()
        try await settle()
        precondition(quitCount == 2)

        // Reopening a player before the deferred callback cancels the quit.
        manager.ensureWindow().close()
        let replacement = manager.ensureWindow()
        try await settle()
        precondition(quitCount == 2 && manager.controllers.count == 1)
        replacement.close()
        // The latest setting must be honored even during the deferred close.
        preferences.set(false, forKey: "quitOnLastPlayerClose")
        try await settle()
        precondition(quitCount == 2)
        let restored = PlayerWindowCoordinator(preferences: preferences, presentsWindows: false,
                                              requestTermination: {})
        precondition(!restored.quitsOnLastPlayerClose)
        print("PASS: default quit-on-last-player, open Settings excluded, other players preserved, disabled background mode, reopen cancellation, live and persisted settings.")
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
}
