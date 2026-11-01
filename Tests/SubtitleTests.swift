import AppKit
import VLCKit
@main struct SubtitleTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  let video = URL(fileURLWithPath: CommandLine.arguments[1])
  let subtitle = video.deletingPathExtension().appendingPathExtension("srt")
  let text = SubtitleFiles.decode(try Data(contentsOf: subtitle), encoding: "自动")!
  precondition(text.contains("经济持续飞速发展的中国"))
  let base = URL(fileURLWithPath: "/tmp/movie.mkv")
  let files = ["other.srt", "movie.en.srt", "movie.zh.ass", "movie.ssa", "movie.srt"].map { URL(fileURLWithPath: "/tmp/" + $0) }
  precondition(SubtitleFiles.candidates(video: base, files: files).map(\.lastPathComponent) == ["movie.srt", "movie.ssa", "movie.zh.ass", "movie.en.srt"])
  let domain = "MoriSubtitleTests." + UUID().uuidString
  let prefs = UserDefaults(suiteName: domain)!
  defer { prefs.removePersistentDomain(forName: domain) }
  let model = PlayerModel(preferences: prefs)
  let view = VLCVideoView(frame: NSRect(x: 0,y: 0,width: 640,height: 360))
  let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = view
  model.player.drawable = view
  model.open(video)
  try await Task.sleep(for: .seconds(4))
  precondition(model.subtitles.message == nil, model.subtitles.message ?? "")
  precondition(model.subtitles.selected >= 0 && !model.subtitles.tracks.isEmpty, "Automatic subtitle selection failed")
  let count = model.subtitles.tracks.count
  model.subtitles.load(subtitle)
  try await Task.sleep(for: .milliseconds(500))
  precondition(model.subtitles.tracks.count == count, "Duplicate track")
  model.subtitles.select(-1)
  try await Task.sleep(for: .milliseconds(500))
  precondition(model.subtitles.selected == -1)
  model.togglePlayback()
  let position = model.elapsed
  model.subtitles.load(subtitle)
  try await Task.sleep(for: .seconds(1))
  precondition(!model.isPlaying && abs(model.elapsed - position) < 1)
  precondition(model.subtitles.selected >= 0)
  let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".srt")
  try text.write(to: copy, atomically: true, encoding: .utf8)
  defer { try? FileManager.default.removeItem(at: copy) }
  model.subtitles.load(copy)
  try await Task.sleep(for: .seconds(2))
  precondition(!model.isPlaying && abs(model.elapsed - position) < 1)
  precondition(model.subtitles.message == nil)
  model.seek(to: 14.5)
  model.togglePlayback()
  try await Task.sleep(for: .seconds(1))
  model.player.saveVideoSnapshot(at: "/tmp/mori-subtitle-test.png", withWidth: 640, andHeight: 360)
  try await Task.sleep(for: .seconds(1))
  prefs.set(false, forKey: "autoLoadSubtitles")
  model.open(video)
  try await Task.sleep(for: .seconds(3))
  let surface = PlaybackSurface()
  surface.model = model
  let drag = SubtitleDrag(url: subtitle)
  precondition(surface.playerView.draggingEntered(drag) == .copy)
  precondition(surface.playerView.prepareForDragOperation(drag))
  precondition(surface.playerView.performDragOperation(drag))
  try await Task.sleep(for: .seconds(2))
  precondition(model.subtitles.selected >= 0, "Renderer drop must activate an external subtitle")
  precondition(model.subtitles.message == nil)
  surface.shutdown()
  model.closePlayback()
  precondition(model.subtitles.tracks.isEmpty)
  print("PASS: GB18030, matching priorities, real automatic load, disable, duplicate suppression, paused selection, cleanup")
 }
}

@MainActor final class SubtitleDrag: NSObject, NSDraggingInfo {
 let draggingPasteboard = NSPasteboard.withUniqueName()
 var draggingDestinationWindow: NSWindow? { nil }
 var draggingSourceOperationMask: NSDragOperation { .copy }
 var draggingLocation: NSPoint { .zero }
 var draggedImageLocation: NSPoint { .zero }
 nonisolated var draggedImage: NSImage? { nil }
 var draggingSource: Any? { nil }
 var draggingSequenceNumber: Int { 1 }
 var draggingFormation: NSDraggingFormation = .none
 var animatesToDestination = false
 var numberOfValidItemsForDrop = 1
 var springLoadingHighlight: NSSpringLoadingHighlight { .none }
 func resetSpringLoading() {}
 func slideDraggedImage(to screenPoint: NSPoint) {}
 nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
 func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
 init(url: URL) { super.init(); draggingPasteboard.writeObjects([url as NSURL]) }
}
