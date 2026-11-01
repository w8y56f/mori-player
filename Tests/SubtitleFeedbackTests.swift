import AppKit
import SwiftUI
import VLCKit
@main struct SubtitleFeedbackTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  let video = URL(fileURLWithPath: CommandLine.arguments[1])
  let srt = video.deletingPathExtension().appendingPathExtension("srt")
  let domain = "MoriSubtitleFeedbackTests." + UUID().uuidString
  let prefs = UserDefaults(suiteName: domain)!
  defer { prefs.removePersistentDomain(forName: domain) }
  let model = PlayerModel(preferences: prefs)
  let view = VLCVideoView(frame: NSRect(x:0,y:0,width:640,height:360))
  let window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
  window.contentView = view; model.player.drawable = view
  model.open(video)
  try await Task.sleep(for:.seconds(3))
  precondition(model.subtitles.selected >= 0 && model.subtitles.feedback == nil, "Auto load must be silent")
  model.subtitles.load(srt)
  try await Task.sleep(for:.milliseconds(300))
  precondition(model.subtitles.feedback?.title == "已启用字幕")
  try await Task.sleep(for:.milliseconds(900))
  model.subtitles.load(srt)
  let latest = model.subtitles.feedback?.id
  try await Task.sleep(for:.milliseconds(500))
  precondition(model.subtitles.feedback?.id == latest && latest != nil, "Old timer must not clear new hint")
  try await Task.sleep(for:.milliseconds(1100))
  precondition(model.subtitles.feedback == nil)
  let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".srt")
  try FileManager.default.copyItem(at:srt,to:copy)
  defer { try? FileManager.default.removeItem(at:copy) }
  model.subtitles.load(copy)
  precondition(model.subtitles.feedback == nil, "Do not announce before track confirmation")
  try await Task.sleep(for:.milliseconds(600))
  precondition(model.subtitles.feedback?.title == "已加载字幕")
  precondition(model.subtitles.feedback?.fileName == copy.lastPathComponent)
  let host = NSHostingView(rootView: SubtitleFeedbackOverlay(subtitles:model.subtitles,playbackSymbol:"play.fill").frame(width:640,height:360))
  host.frame = NSRect(x:0,y:0,width:640,height:360); host.layoutSubtreeIfNeeded()
  if let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
   host.cacheDisplay(in:host.bounds,to:bitmap)
   try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/mori-subtitle-feedback.png"))
  }
  try await Task.sleep(for:.milliseconds(1600))
  model.subtitles.changeSize(150)
  try await Task.sleep(for:.milliseconds(700))
  precondition(model.subtitles.feedback == nil, "Size changes must be silent")
  model.subtitles.changeEncoding("GB18030")
  try await Task.sleep(for:.milliseconds(700))
  precondition(model.subtitles.feedback == nil, "Encoding changes must be silent")
  model.subtitles.load(copy)
  try await Task.sleep(for:.milliseconds(300))
  precondition(model.subtitles.feedback != nil)
  model.closePlayback()
  precondition(model.subtitles.feedback == nil)
  model.open(video)
  try await Task.sleep(for:.seconds(2))
  precondition(model.subtitles.feedback == nil, "Old request must not announce in another load")
  model.subtitles.load(URL(fileURLWithPath:"/missing/subtitle.srt"))
  precondition(model.subtitles.feedback == nil && model.subtitles.message != nil)
  model.closePlayback()
  print("PASS: confirmed load, cached activation, 1.5s timer, replacement, silent auto/size/encoding, errors and reset")
 }
}
