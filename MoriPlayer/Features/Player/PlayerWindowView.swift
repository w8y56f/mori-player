import SwiftUI

struct PlayerWindowView: View {
    @AppStorage("seekStepSeconds") private var seekStepSeconds = 5
    @AppStorage("appLanguage") private var appLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var model: PlayerModel
    let onOpenFile: () -> Void
    @State private var scrubbing = false
    @State private var scrubTime = 0.0

    var body: some View {
        VStack(spacing: 0) {
            videoArea
                .overlay(alignment: .bottom) {
                    if model.isFullScreen {
                        controls
                            .opacity(model.areControlsVisible ? 1 : 0)
                            .allowsHitTesting(model.areControlsVisible)
                            .accessibilityHidden(!model.areControlsVisible)
                            .animation(.easeOut(duration: 0.15), value: model.areControlsVisible)
                    }
                }
            if !model.isFullScreen { controls }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.fileName ?? "Mori Player")
        .onChange(of: model.isFullScreen) { _, _ in scrubbing = false }
        .onChange(of: model.isLoading) { _, loading in if loading { scrubbing = false } }
        .alert(L("无法播放"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("好")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var videoArea: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            PlayerSurface(model: model)
            if !model.canPlay && !model.isLoading {
                VStack(spacing: 18) {
                    Image("AppMark")
                        .resizable().frame(width: 96, height: 96)
                    Text(AppBuildInfo.read().name)
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                    Text(L("打开一段影像，让时间慢下来。"))
                        .foregroundStyle(.secondary)
                    Button(L("打开文件…"), action: onOpenFile)
                        .buttonStyle(.borderedProminent)
                    Text(L("拖入视频或音频，或按 ⌘O 打开"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(32)
            }
            if model.isLoading { ProgressView(L("正在载入…")).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            if model.canPlay {
                SubtitleFeedbackOverlay(subtitles: model.subtitles, playbackSymbol: model.playbackHint?.rawValue, seekText: model.seekHint)
                    .onReceive(model.subtitles.$feedback) { if $0 != nil { model.clearCentralHints() } }
            }
            if model.canPlay && model.isSpeedVisible {
                VStack {
                    HStack {
                        Text(String(format: "%.2f×", model.speed))
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    Spacer()
                }.padding(16).allowsHitTesting(false)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                skipButton(forward: false)
                control(model.isPlaying ? "pause.fill" : "play.fill", L("播放 / 暂停（空格）"), prominent: true) { model.togglePlayback() }
                skipButton(forward: true)
                control("stop.fill", L("停止并回到开头")) { model.stop() }
            }.disabled(!model.canPlay)
            Toggle(isOn: $model.isPinned) {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 29, height: 28)
            }
            .toggleStyle(PinToggleStyle())
            .help(model.isPinned ? L("取消窗口置顶") : L("窗口置顶"))
            .accessibilityLabel(L("窗口置顶"))
            Text("\(PlayerModel.time(scrubbing ? scrubTime : model.elapsed)) / \(PlayerModel.time(model.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).fixedSize()
            SeekBar(value: model.elapsed, duration: model.duration, isEnabled: model.canPlay,
                onPreview: { target in
                    scrubbing = target != nil
                    if let target { scrubTime = target }
                }, onSeek: model.seek(to:), onEditingChanged: model.setControlsInteracting)
            Text("−\(PlayerModel.time(max(0, model.duration - (scrubbing ? scrubTime : model.elapsed))))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).fixedSize()
            SubtitleButton(subtitles: model.subtitles, enabled: model.canPlay, interaction: model.setSubtitleMenuVisible)
                .foregroundStyle(controlActiveState == .key ? Color.primary : Color.secondary)
            HStack(spacing: 7) {
                Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 20, alignment: .center)
                Slider(value: $model.volume, in: 0...1, onEditingChanged: model.setControlsInteracting)
                    .tint(controlActiveState == .key ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                    .frame(width: 85).accessibilityLabel(L("音量"))
                    .help(L("音量") + " \(Int(model.volume * 100))%" + L("（↑ / ↓）"))
            }
            control("arrow.up.left.and.arrow.down.right", L("切换全屏（⌃⌘F）")) { model.toggleFullScreen() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { (colorScheme == .dark ? Color.white : Color.black).opacity(0.08).frame(height: 1) }
        .animation(.easeOut(duration: 0.15), value: controlActiveState)
        .contentShape(Rectangle())
        .onHover(perform: model.setControlsHovered)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in model.setControlsInteracting(true) }
            .onEnded { _ in model.setControlsInteracting(false) })
    }

    private func skipButton(forward: Bool) -> some View {
        Button { model.skip(forward: forward) } label: {
            ZStack {
                Image(systemName: forward ? "goforward" : "gobackward").font(.system(size: 18))
                Text("\(model.seekStep)").font(.system(size: 8, weight: .semibold).monospacedDigit()).offset(y: 1)
            }.frame(width: 29, height: 28)
        }.buttonStyle(.plain)
        .help(L(forward ? "快进" : "快退") + " \(model.seekStep) " + L("秒") + (forward ? " (→)" : " (←)"))
    }

    private func control(_ symbol: String, _ label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 14, weight: .medium))
                .foregroundStyle(controlActiveState == .key ? Color.primary : Color.secondary)
                .frame(width: 29, height: 28)
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// System button tint becomes neutral in inactive windows. Draw the selected
/// state explicitly so that pin status remains visible regardless of focus.
private struct PinToggleStyle: ToggleStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    private let forestGreen = Color(red: 0.29, green: 0.49, blue: 0.38)

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .foregroundStyle(configuration.isOn ? Color.white :
                    (controlActiveState == .key ? Color.primary : Color.secondary))
                .frame(width: 40, height: 36)
                .background(configuration.isOn ? forestGreen : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? L("已置顶") : L("未置顶"))
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}
