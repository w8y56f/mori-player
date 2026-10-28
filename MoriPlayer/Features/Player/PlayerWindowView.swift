import SwiftUI

struct PlayerWindowView: View {
    @ObservedObject var model: PlayerModel
    @State private var scrubbing = false
    @State private var scrubTime = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                PlayerSurface(model: model)
                if !model.canPlay && !model.isLoading {
                    VStack(spacing: 18) {
                        Image("AppMark")
                            .resizable().frame(width: 96, height: 96)
                        Text("Mori Player")
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                        Text("打开一段影像，让时间慢下来。")
                            .foregroundStyle(.secondary)
                        Button("打开文件…", action: model.openFile)
                            .buttonStyle(.borderedProminent)
                        Text("⌘O 打开视频或音频")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(32)
                }
                if model.isLoading { ProgressView("正在载入…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                if model.canPlay && model.speed != 1 {
                    VStack {
                        HStack {
                            Spacer()
                            Text(String(format: "%.2g×", model.speed))
                                .font(.caption.monospacedDigit())
                                .padding(8).background(.black.opacity(0.6), in: Capsule())
                        }
                        Spacer()
                    }.padding(16).allowsHitTesting(false)
                }
            }
            controls
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 800, minHeight: 400)
        .navigationTitle(model.fileName ?? "Mori Player")
        .alert("无法播放", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                control("gobackward.5", "快退 5 秒（←）") { model.seek(by: -5) }
                control(model.isPlaying ? "pause.fill" : "play.fill", "播放 / 暂停（空格）", prominent: true) { model.togglePlayback() }
                control("goforward.5", "快进 5 秒（→）") { model.seek(by: 5) }
                control("stop.fill", "停止并回到开头") { model.stop() }
            }.disabled(!model.canPlay)
            Text("\(PlayerModel.time(scrubbing ? scrubTime : model.elapsed)) / \(PlayerModel.time(model.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).fixedSize()
            Slider(value: Binding(get: { scrubbing ? scrubTime : model.elapsed }, set: { value in
                scrubTime = value
                if !scrubbing { model.seek(to: value) }
            }), in: 0...max(model.duration, 1), onEditingChanged: { editing in
                if editing { scrubTime = model.elapsed }
                scrubbing = editing
                if !editing { model.seek(to: scrubTime) }
            })
            .disabled(!model.canPlay).accessibilityLabel("播放进度")
            Text("−\(PlayerModel.time(max(0, model.duration - (scrubbing ? scrubTime : model.elapsed))))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).fixedSize()
            HStack(spacing: 7) {
                Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $model.volume, in: 0...1)
                    .frame(width: 85).accessibilityLabel("音量")
                    .help("音量 \(Int(model.volume * 100))%（↑ / ↓）")
            }
            control("arrow.up.left.and.arrow.down.right", "切换全屏（⌃⌘F）") { model.toggleFullScreen() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.105))
        .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
    }

    private func control(_ symbol: String, _ label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 14, weight: .medium))
                .frame(width: 29, height: 28)
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
