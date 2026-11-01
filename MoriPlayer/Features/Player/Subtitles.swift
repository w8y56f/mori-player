import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VLCKit

struct SubtitleCandidate: Identifiable {
    let url: URL
    var id: URL { url }
}

enum SubtitleFiles {
    static let extensions = ["srt", "ass", "ssa", "vtt", "smi", "sub", "idx"]
    static func accepts(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    static func candidates(video: URL, files: [URL]) -> [URL] {
        let stem = video.deletingPathExtension().lastPathComponent.lowercased()
        let languages = ["zh", "zh-cn", "zh-tw", "chs", "cht", "en", "eng", "ja", "jp", "ko", "fr", "de", "es"]
        func rank(_ url: URL) -> Int {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            if name == stem { return 0 }
            let suffix = String(name.dropFirst(stem.count + 1))
            return ["zh", "zh-cn", "zh-tw", "chs", "cht"].contains(suffix) ? 1 : 2
        }
        return files.filter {
            let name = $0.deletingPathExtension().lastPathComponent.lowercased()
            return ["srt", "ass", "ssa"].contains($0.pathExtension.lowercased()) &&
                (name == stem || (name.hasPrefix(stem + ".") && languages.contains(String(name.dropFirst(stem.count + 1)))))
        }.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            let a = extensions.firstIndex(of: $0.pathExtension.lowercased())!, b = extensions.firstIndex(of: $1.pathExtension.lowercased())!
            return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
        }
    }
    static func decode(_ data: Data, encoding: String) -> String? {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let choices: [String.Encoding]
        switch encoding {
        case "UTF-8": choices = [.utf8]
        case "GB18030": choices = [gb]
        case "Big5": choices = [big5]
        default:
            choices = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? [.utf16] : [.utf8, gb, big5]
        }
        return choices.lazy.compactMap { String(data: data, encoding: $0) }.first
    }
}

@MainActor
final class SubtitleController: ObservableObject {
    enum LoadOrigin { case user, automatic, appearance }
    struct Feedback: Identifiable {
        let id = UUID()
        let title: String
        let fileName: String
    }
    @Published private(set) var feedback: Feedback?
    private var feedbackTask: Task<Void, Never>?
    private var pendingOrigin: LoadOrigin = .automatic
    private var requestID = UUID()
    private var awaitingFeedback: (request: UUID, track: Int32, url: URL, reused: Bool)?
    func dismissFeedback() { clearFeedback() }
    private func clearFeedback() {
        feedbackTask?.cancel(); feedbackTask = nil; feedback = nil
    }
    private func confirmFeedback() {
        guard let notice = awaitingFeedback, notice.request == requestID,
              player.currentVideoSubTitleIndex == notice.track else { return }
        awaitingFeedback = nil
        clearFeedback()
        let next = Feedback(title: notice.reused ? "已启用字幕" : "已加载字幕", fileName: notice.url.lastPathComponent)
        feedback = next
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard let self, self.feedback?.id == next.id else { return }
            self.feedback = nil; self.feedbackTask = nil
        }
    }
    @Published var candidates: [SubtitleCandidate] = []
    @Published var tracks: [(id: Int32, name: String)] = []
    @Published var selected: Int32 = -1
    @Published var message: String?
    @Published var needsFolderAccess = false
    @Published var encoding = "自动"
    @Published private(set) var sizePercent = 100
    private var scaledTracks: [String: Int32] = [:]
    private var trackSources: [Int32: URL] = [:]
    private var pendingKey: String?
    private var queuedScale: URL?
    var visibleTracks: [(id: Int32, name: String)] {
        tracks.filter { track in
            guard let source = trackSources[track.id] else { return true }
            return loaded[source] == track.id
        }.map { track in
            (id: track.id, name: trackSources[track.id]?.lastPathComponent ?? track.name)
        }
    }
    var canScale: Bool { trackSources[selected]?.pathExtension.lowercased() == "srt" }
    var sizeUnavailableReason: String { selected == -1 ? L("请选择外挂 SRT 字幕后调整大小") : L("当前仅支持外挂 SRT 字幕大小调整") }
    func changeSize(_ value: Int) {
        guard canScale, let source = trackSources[selected] else { return }
        sizePercent = min(200, max(50, (value / 10) * 10))
        preferences.set(sizePercent, forKey: "subtitleSizePercent")
        if pending != nil { queuedScale = source } else { load(source, origin: .appearance, reload: true) }
    }
    private let player: VLCMediaPlayer
    private let preferences: UserDefaults
    private var video: URL?
    private var generation = UUID()
    private var deferred: (url: URL, origin: LoadOrigin, reload: Bool)?
    private var automaticPending = false
    private var manualChoice = false
    private var loaded: [URL: Int32] = [:]
    private var pending: (URL, Set<Int32>)?
    private var lastExternal: URL?
    private var scopes: [URL] = []
    private var temporary: [URL] = []
    init(player: VLCMediaPlayer, preferences: UserDefaults) {
        self.player = player; self.preferences = preferences
        let saved = preferences.integer(forKey: "subtitleSizePercent")
        sizePercent = (50...200).contains(saved) && saved % 10 == 0 ? saved : 100
    }

    func reset(video: URL? = nil) {
        clearFeedback(); awaitingFeedback = nil; requestID = UUID()
        for url in scopes { url.stopAccessingSecurityScopedResource() }
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        scaledTracks = [:]; trackSources = [:]; pendingKey = nil; queuedScale = nil
        scopes = []; temporary = []; loaded = [:]; pending = nil; lastExternal = nil
        candidates = []; tracks = []; selected = -1; message = nil; needsFolderAccess = false
        generation = UUID(); deferred = nil
        self.video = video; manualChoice = false; automaticPending = video != nil; encoding = "自动"
        guard let video else { return }
        let key = video.deletingLastPathComponent().standardizedFileURL.path
        let bookmarks = preferences.dictionary(forKey: "subtitleFolderBookmarks") as? [String: Data] ?? [:]
        if let data = bookmarks[key] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                retainAccess(url)
                if stale, let updated = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    var next = bookmarks; next[key] = updated; preferences.set(next, forKey: "subtitleFolderBookmarks")
                }
            }
        }
        discover()
    }
    private func retainAccess(_ url: URL) {
        if !scopes.contains(url), url.startAccessingSecurityScopedResource() { scopes.append(url) }
    }
    private func discover() {
        guard let video else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: video.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            candidates = SubtitleFiles.candidates(video: video, files: files).map { SubtitleCandidate(url: $0) }
            needsFolderAccess = false
        } catch { needsFolderAccess = true }
    }
    func refresh() {
        let ids = (player.videoSubTitlesIndexes as? [NSNumber] ?? []).map { $0.int32Value }
        let names = player.videoSubTitlesNames as? [String] ?? []
        let next = zip(ids, names).filter { $0.0 >= 0 }.map { (id: $0.0, name: $0.1) }
        if tracks.map(\.id) != next.map(\.id) || tracks.map(\.name) != next.map(\.name) { tracks = next }
        if let (url, previous) = pending, let added = ids.first(where: { $0 >= 0 && !previous.contains($0) }) {
            loaded[url] = added; trackSources[added] = url
            if let key = pendingKey { scaledTracks[key] = added }
            pendingKey = nil; pending = nil
            player.currentVideoSubTitleIndex = added
            if pendingOrigin == .user { awaitingFeedback = (requestID, added, url, false) }
        }
        if pending == nil, let source = queuedScale {
            queuedScale = nil; load(source, origin: .appearance, reload: true)
        }
        if selected != player.currentVideoSubTitleIndex { selected = player.currentVideoSubTitleIndex }
        confirmFeedback()
        guard video != nil, player.isPlaying || player.state == .paused else { return }
        if let request = deferred { deferred = nil; load(request.url, origin: request.origin, reload: request.reload); return }
        if automaticPending {
            automaticPending = false
            if !manualChoice, preferences.object(forKey: "autoLoadSubtitles") as? Bool ?? true, let first = candidates.first {
                load(first.url, origin: .automatic)
            }
        }
    }
    func select(_ id: Int32) {
        requestID = UUID(); awaitingFeedback = nil; deferred = nil
        manualChoice = true; queuedScale = nil; pending = nil; pendingKey = nil
        if let source = trackSources[id] { loaded[source] = id }
        player.currentVideoSubTitleIndex = id; selected = id
    }
    func load(_ url: URL, origin: LoadOrigin = .user, reload: Bool = false) {
        guard video != nil, player.media != nil else { message = L("请先打开视频，再加载字幕。"); return }
        if !player.isPlaying && player.state != .paused { deferred = (url, origin, reload); if origin != .automatic { manualChoice = true }; return }
        guard pending == nil else { message = L("字幕正在加载，请稍后再试。"); return }
        if origin != .automatic { manualChoice = true }
        requestID = UUID(); awaitingFeedback = nil
        if origin == .user { clearFeedback() }
        func activateCached(_ id: Int32) {
            select(id)
            if origin == .user { awaitingFeedback = (requestID, id, url, true); confirmFeedback() }
        }
        retainAccess(url)
        let cacheKey = url.standardizedFileURL.path + "|" + encoding + "|" + String(sizePercent)
        if let id = scaledTracks[cacheKey] { activateCached(id); return }
        if url.pathExtension.lowercased() != "srt", !reload, let id = loaded[url] { activateCached(id); return }
        do {
            var source = url
            let ext = url.pathExtension.lowercased()
            if ext == "idx" || ext == "sub" {
                let idx = url.deletingPathExtension().appendingPathExtension("idx")
                let sub = url.deletingPathExtension().appendingPathExtension("sub")
                if ext == "idx" || FileManager.default.fileExists(atPath: idx.path) {
                    guard FileManager.default.isReadableFile(atPath: idx.path), FileManager.default.isReadableFile(atPath: sub.path) else {
                        throw NSError(domain: "Subtitles", code: 1, userInfo: [NSLocalizedDescriptionKey: L("IDX/SUB 需要同名的两个文件均可读取，请授权所在文件夹后重试。")])
                    }
                    source = idx
                }
            }
            if source.pathExtension.lowercased() != "idx" {
                let data = try Data(contentsOf: source)
                guard let text = SubtitleFiles.decode(data, encoding: encoding) else {
                    throw NSError(domain: "Subtitles", code: 2, userInfo: [NSLocalizedDescriptionKey: L("无法识别字幕文字编码，请在字幕编码菜单中手动选择。")])
                }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MoriSubtitles-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                temporary.append(folder)
                if ext == "srt" {
                    source = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".ass")
                    let size = player.videoSize
                    let aspect = size.height > 0 ? size.width / size.height : 16.0 / 9
                    try SRTScaling.ass(from: text, percent: sizePercent, aspect: aspect).write(to: source, atomically: true, encoding: .utf8)
                } else {
                    source = folder.appendingPathComponent(url.lastPathComponent)
                    try text.write(to: source, atomically: true, encoding: .utf8)
                }
            }
            let old = Set(tracks.map(\.id))
            guard player.addPlaybackSlave(source, type: .subtitle, enforce: true) == 0 else {
                throw NSError(domain: "Subtitles", code: 3, userInfo: [NSLocalizedDescriptionKey: L("播放内核未能加载此字幕。")])
            }
            pendingOrigin = origin
            pendingKey = cacheKey
            pending = (url, old); lastExternal = url
            if !candidates.contains(where: { $0.url == url }) { candidates.append(SubtitleCandidate(url: url)) }
            let media = generation
            let request = requestID
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.generation == media, self.requestID == request, self.pending?.0 == url, self.pendingKey == cacheKey else { return }
                self.pending = nil; self.pendingKey = nil; self.queuedScale = nil; self.message = L("未能识别字幕轨道，请检查字幕格式和文件内容。")
            }
        } catch { message = error.localizedDescription }
    }
    func changeEncoding(_ value: String) {
        encoding = value
        if let lastExternal { load(lastExternal, origin: .appearance, reload: true) }
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = L("加载字幕文件…")
        panel.allowedContentTypes = SubtitleFiles.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.directoryURL = video?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func authorizeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = video?.deletingLastPathComponent()
        panel.message = L("选择字幕所在文件夹，允许播放器读取字幕及配套文件。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        retainAccess(url)
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = preferences.dictionary(forKey: "subtitleFolderBookmarks") as? [String: Data] ?? [:]
            bookmarks[url.standardizedFileURL.path] = bookmark
            preferences.set(bookmarks, forKey: "subtitleFolderBookmarks")
            discover(); automaticPending = !manualChoice
        } catch { message = error.localizedDescription }
    }
}

struct SubtitleButton: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @ObservedObject var subtitles: SubtitleController
    let enabled: Bool
    let interaction: (Bool) -> Void
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "captions.bubble").frame(width: 28, height: 28)
        }
        .buttonStyle(.plain).help(L("字幕")).accessibilityLabel(L("字幕")).disabled(!enabled)
        .onChange(of: presented) { _, value in interaction(value) }
        .popover(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 10) {
                Button(L("加载字幕文件…")) { subtitles.chooseFile() }
                Button(L("允许访问字幕所在文件夹…")) { subtitles.authorizeFolder() }
                if subtitles.needsFolderAccess { Text(L("自动查找需要访问视频所在文件夹。")).font(.caption) }
                Divider()
                Button(subtitles.selected == -1 ? L("✓ 关闭字幕") : L("关闭字幕")) { subtitles.select(-1) }
                ForEach(subtitles.visibleTracks, id: \.id) { track in
                    Button((subtitles.selected == track.id ? "✓ " : "") + track.name) { subtitles.select(track.id) }
                }
                ForEach(subtitles.candidates) { candidate in
                    Button(candidate.url.lastPathComponent) { subtitles.load(candidate.url) }
                }
                Divider()
                Menu(L("字幕大小：") + "\(subtitles.sizePercent)%") {
                    Button(L("缩小 10%")) { subtitles.changeSize(subtitles.sizePercent - 10) }.disabled(subtitles.sizePercent <= 50)
                    Button(L("放大 10%")) { subtitles.changeSize(subtitles.sizePercent + 10) }.disabled(subtitles.sizePercent >= 200)
                    Button(L("恢复默认（100%）")) { subtitles.changeSize(100) }
                    Divider()
                    ForEach(Array(stride(from: 50, through: 200, by: 10)), id: \.self) { value in
                        Button((subtitles.sizePercent == value ? "✓ " : "") + "\(value)%") { subtitles.changeSize(value) }
                    }
                }.disabled(!subtitles.canScale)
                if !subtitles.canScale { Text(subtitles.sizeUnavailableReason).font(.caption).foregroundStyle(.secondary) }
                Picker(L("字幕编码"), selection: Binding(get: { subtitles.encoding }, set: { subtitles.changeEncoding($0) })) {
                    ForEach(["自动", "UTF-8", "GB18030", "Big5"], id: \.self) { Text(L($0)).tag($0) }
                }
            }.padding().frame(minWidth: 260, maxWidth: 420)
        }
        .alert(L("字幕"), isPresented: Binding(get: { subtitles.message != nil }, set: { if !$0 { subtitles.message = nil } })) {
            Button(L("好")) { subtitles.message = nil }
        } message: { Text(subtitles.message ?? "") }
    }
}

/// Observe the nested controller directly: PlayerModel does not republish it.
struct SubtitleFeedbackOverlay: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @ObservedObject var subtitles: SubtitleController
    let playbackSymbol: String?
    var seekText: String? = nil
    var volumePercent: Int? = nil
    var body: some View {
        Group {
            if let feedback = subtitles.feedback {
                VStack(spacing: 8) {
                    Label(L(feedback.title), systemImage: "captions.bubble")
                        .font(.system(size: 22, weight: .medium))
                    Text(feedback.fileName).font(.system(size: 12))
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(20).frame(maxWidth: 320)
                .foregroundStyle(.white)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                .id(feedback.id).transition(.opacity)
            } else if let seekText {
                Text(seekText).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white).padding(20)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            } else if let volumePercent {
                Label(L("音量") + " \(volumePercent)%",
                      systemImage: volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white).padding(20)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            } else if let playbackSymbol {
                Image(systemName: playbackSymbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white).frame(width: 84, height: 84)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.15), value: subtitles.feedback?.id)
        .allowsHitTesting(false)
    }
}
