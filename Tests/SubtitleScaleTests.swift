import AppKit
import VLCKit
@main struct SubtitleScaleTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  let sample = "1\n00:00:01,234 --> 00:00:02,999\n<b>你好</b>\n第二行 {\\pos(1,1)}\n"
  let generated = try SRTScaling.ass(from: sample, percent: 150)
  precondition(generated.contains("Default,PingFang SC,54.0"))
  precondition(generated.contains("0:00:01.23,0:00:02.99"))
  precondition(generated.contains("{\\b1}你好{\\b0}\\N第二行 \\{"))
  let domain = "MoriScaleTests." + UUID().uuidString
  let prefs = UserDefaults(suiteName: domain)!
  defer { prefs.removePersistentDomain(forName: domain) }
  let model = PlayerModel(preferences: prefs)
  let view = VLCVideoView(frame: NSRect(x:0,y:0,width:640,height:360))
  let window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
  window.contentView = view; model.player.drawable = view
  model.open(URL(fileURLWithPath:CommandLine.arguments[1]))
  try await Task.sleep(for:.seconds(4))
  precondition(model.subtitles.canScale)
  model.seek(to:14)
  for scale in [50,100,150,200] {
   model.subtitles.changeSize(scale)
   try await Task.sleep(for:.seconds(1))
   model.seek(to:14)
   try await Task.sleep(for:.milliseconds(500))
   precondition(model.isPlaying && model.subtitles.message == nil)
   model.player.saveVideoSnapshot(at:"/tmp/mori-scale-\(scale).png",withWidth:640,andHeight:360)
   try await Task.sleep(for:.milliseconds(300))
  }
  model.togglePlayback()
  let position = model.elapsed
  let tracks = model.subtitles.tracks.count
  model.subtitles.changeSize(100)
  try await Task.sleep(for:.milliseconds(500))
  precondition(!model.isPlaying && abs(model.elapsed-position)<1)
  precondition(model.subtitles.tracks.count == tracks, "Cached size must reuse tracks")
  for size in [110,120,130,140] { model.subtitles.changeSize(size) }
  try await Task.sleep(for:.seconds(2))
  precondition(model.subtitles.sizePercent == 140 && model.subtitles.message == nil)
  precondition(!model.isPlaying && abs(model.elapsed-position)<1)
  let another = PlayerModel(preferences:prefs)
  precondition(another.subtitles.sizePercent == 140)
  another.closePlayback()
  model.subtitles.select(-1)
  model.subtitles.changeSize(200)
  precondition(model.subtitles.selected == -1)
  model.closePlayback()
  print("PASS: SRT conversion, formatting, sizes, caching, paused rapid changes, persistence, disabled subtitles")
 }
}
