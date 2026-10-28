import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键与操作").font(.title2.bold())
                    Text("在播放器窗口中使用以下操作。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            GroupBox("文件与播放") {
                VStack(spacing: 12) {
                    row("打开文件", "⌘ O")
                    row("播放 / 暂停", "空格", note: "也可单击播放区域或播放 / 暂停按钮")
                    row("停止并回到开头", "停止按钮")
                    row("切换全屏", "⌃ ⌘ F", note: "也可双击播放区域或点击全屏按钮")
                    row("退出全屏", "Esc")
                }.padding(10)
            }
            GroupBox("跳转与音量") {
                VStack(spacing: 12) {
                    row("快退 / 快进 5 秒", "← / →")
                    row("增大 / 减小音量", "↑ / ↓", note: "每次调整 5%；播放区域内滚轮向上增大、向下减小")
                    row("跳转到指定时间", "拖动进度条")
                }.padding(10)
            }
            GroupBox("播放速度") {
                VStack(spacing: 12) {
                    row("加速 0.25×", "A")
                    row("减速 0.25×", "S")
                    Text("范围 0.25×–4×；暂停时也可调整，下次播放时生效。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10)
            }
            Text("⌃ Control    ⌘ Command    ·    Settings：⌘ ,")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, _ keys: String, note: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(keys).font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
        }
    }
}
