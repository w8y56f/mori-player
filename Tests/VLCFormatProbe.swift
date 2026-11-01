import AppKit
import VLCKit
@main struct Probe {
 @MainActor static func main() async {
  _ = NSApplication.shared
  guard CommandLine.arguments.count == 2 else { fatalError("Pass one video file path") }
  let domain = "MoriFormatProbe.\(UUID().uuidString)"
  let preferences = UserDefaults(suiteName: domain)!
  defer { preferences.removePersistentDomain(forName: domain) }
  let p = PlayerModel(preferences: preferences)
  let view = VLCVideoView(frame: NSRect(x:0,y:0,width:640,height:360))
  let w = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
  w.contentView = view
  p.player.drawable = view
  p.open(URL(fileURLWithPath:CommandLine.arguments[1]))
  try? await Task.sleep(for:.seconds(6))
  let stats = p.player.media!.statistics
  print("RESULT duration=\(p.duration) elapsed=\(p.elapsed) video=\(stats.decodedVideo) audio=\(stats.decodedAudio) displayed=\(stats.displayedPictures) error=\(p.errorMessage ?? "none")")
  precondition(stats.decodedVideo > 0 && stats.displayedPictures > 0, "No video output")
  precondition(p.errorMessage == nil && p.duration > 0, "Load failed")
  p.togglePlayback()
  try? await Task.sleep(for:.milliseconds(500))
  precondition(!p.isPlaying, "Pause failed")
  let target = min(30, p.duration / 2)
  p.seek(to: target)
  try? await Task.sleep(for:.seconds(1))
  precondition(abs(p.elapsed - target) < 3, "Seek failed")
  p.changeSpeed(by: 0.25)
  p.togglePlayback()
  try? await Task.sleep(for:.seconds(1))
  precondition(p.isPlaying && p.speed == 1.25, "Resume failed")
  p.stop()
  try? await Task.sleep(for:.milliseconds(500))
  precondition(!p.isPlaying && p.elapsed < 3, "Stop failed")
  p.closePlayback()
  print("CONTROLS PASS")
 }
}
