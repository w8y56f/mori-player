import AppKit
@main struct SeekStepTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  let domain = "MoriSeekTests." + UUID().uuidString
  let prefs = UserDefaults(suiteName:domain)!
  defer { prefs.removePersistentDomain(forName:domain) }
  let m = PlayerModel(preferences:prefs)
  precondition(m.seekStep == 5)
  prefs.set(999,forKey:"seekStepSeconds"); precondition(m.seekStep == 5)
  m.open(URL(fileURLWithPath:CommandLine.arguments[1]))
  try await Task.sleep(for:.seconds(3))
  m.togglePlayback(); m.seek(to:20)
  prefs.set(10,forKey:"seekStepSeconds")
  m.skip(forward:true)
  precondition(m.elapsed == 30 && m.seekHint != nil && !m.isPlaying)
  try await Task.sleep(for:.milliseconds(600))
  m.skip(forward:false)
  try await Task.sleep(for:.milliseconds(600))
  precondition(m.seekHint != nil && abs(m.elapsed-20)<1)
  try await Task.sleep(for:.milliseconds(500))
  precondition(m.seekHint == nil)
  m.seek(to:0); m.skip(forward:false); precondition(m.seekHint == nil)
  m.skip(forward:true); m.closePlayback(); precondition(m.seekHint == nil)
  print("PASS: default, validation, configured jumps, paused state, timer restart and cleanup")
 }
}
