import SwiftUI

struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared
    @AppStorage("seekStepSeconds") private var seekStepSeconds = 5
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("autoLoadSubtitles") private var autoLoadSubtitles = true
    @AppStorage("activateOnFirstClick") private var activateOnFirstClick = true
    @AppStorage("rememberPlaybackPosition") private var rememberPlaybackPosition = true
    @AppStorage("reverseVolumeScroll") private var reverseVolumeScroll = true
    @AppStorage("allowMultipleWindows") private var allowMultipleWindows = false
    @AppStorage("quitOnLastPlayerClose") private var quitOnLastPlayerClose = true
    @AppStorage("initialWindowSizeMode") private var initialWindowSizeMode: InitialWindowSizeMode = .smart
    @AppStorage("initialVolumeMode") private var initialVolumeMode: InitialVolumeMode = .remember
    @AppStorage("fixedInitialVolume") private var fixedInitialVolume = VolumePreferences.defaultVolume
    @ObservedObject var appearanceController: AppearanceController

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            generalPanel
                .tabItem { Label(L("General（通用）"), systemImage: "gearshape") }.tag(0)
            appearancePanel
                .tabItem { Label(L("外观"), systemImage: "circle.lefthalf.filled") }.tag(1)
            ScrollView {
                shortcutsPanel
            }
            .tabItem { Label(L("快捷键与操作"), systemImage: "keyboard") }.tag(2)
            AboutView()
                .tabItem { Label(L("关于"), systemImage: "info.circle") }.tag(3)
        }
        .onChange(of: seekStepSeconds) { _, value in if !(1...60).contains(value) { seekStepSeconds = 5 } }
        .onChange(of: appLanguage) { _, _ in LanguageMenuController.synchronize() }
        .frame(width: 580, height: 620)
        .modifier(PlayerAppearanceModifier(controller: appearanceController))
    }

    private var generalPanel: some View {
        Form {
            Section(L("语言")) {
                Picker(L("语言"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).id(appLanguage + language.rawValue).tag(language.rawValue) }
                }
                Text(L("语言更改立即生效。系统语言不受支持时使用英文。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("窗口")) {
                Picker(L("播放器初始大小"), selection: $initialWindowSizeMode) {
                    ForEach(InitialWindowSizeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
                Text(L("智能适配屏幕按视频比例选择合适大小；记住上次窗口大小会恢复手动调整的尺寸；原始尺寸以实际像素 1:1 为目标，过大时缩小到屏幕内。"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(L("手动调整后，同一窗口后续视频保持大小；同组标签页共用尺寸。设置对之后打开的视频或新窗口生效。"))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("关闭最后一个播放窗口时退出应用"), isOn: $quitOnLastPlayerClose)
                Text(L("默认开启。关闭最后一个播放窗口或标签页会彻底退出，Settings 也会关闭。关闭此选项后，应用继续在后台运行，可通过 Dock 再次打开播放器。"))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(L("允许多个播放窗口"), isOn: $allowMultipleWindows)
                Text(L("默认使用单个窗口。开启后，打开新文件会创建独立播放窗口，各窗口可同时播放；拖入已有窗口则替换该窗口的视频。关闭选项不会自动关闭已有窗口。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("字幕")) {
                Toggle(L("自动加载同目录字幕"), isOn: $autoLoadSubtitles)
                Text(L("优先同名 SRT、ASS、SSA，其次匹配语言后缀。可将字幕拖入视频区域，或点击控制栏的字幕按钮加载、切换和关闭字幕。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("播放")) {
                Stepper(value: $seekStepSeconds, in: 1...60) {
                    HStack {
                        Text(L("快进／快退步长"))
                        TextField("", value: $seekStepSeconds, format: .number).frame(width: 45)
                        Text(L("秒"))
                    }
                }
                HStack {
                    ForEach([5,10,15,30,60], id: \.self) { n in Button("\(n) " + L("秒")) { seekStepSeconds = n } }
                }

                Toggle(L("记住播放位置"), isOn: $rememberPlaybackPosition)
                Text(L("再次打开同一文件时从上次位置继续。播放结束或点击停止后从头播放。记录保存在应用的持久配置中，关闭此选项后不读取或更新记录。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("初始音量")) {
                Picker(L("策略"), selection: $initialVolumeMode) {
                    ForEach(InitialVolumeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
                if initialVolumeMode == .fixed {
                    HStack(spacing: 12) {
                        Slider(value: Binding(
                            get: { VolumePreferences.validated(fixedInitialVolume) },
                            set: { fixedInitialVolume = $0 }), in: 0...1, step: 0.01)
                            .accessibilityLabel(L("固定初始音量"))
                        Text("\(Int((VolumePreferences.validated(fixedInitialVolume) * 100).rounded()))%")
                            .font(.callout.monospacedDigit())
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Text(L("记忆模式会保存最近一次调整的音量，包括静音；首次使用为 70%。固定模式使用指定初始值，不覆盖之前的记忆记录。"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(L("仅影响之后创建的播放窗口。已有窗口音量互不联动，同一窗口切换视频保留当前音量。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("鼠标操作")) {
                Toggle(L("首次点击仅激活窗口"), isOn: $activateOnFirstClick)
                Text(L("开启后，播放器失焦时，第一次点击播放区域只激活窗口，不改变播放状态；再次点击才播放或暂停。适用于播放与暂停状态。"))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(L("反转滚轮音量方向"), isOn: $reverseVolumeScroll)
                Text(L("播放或暂停、聚焦或失焦时，均可按住播放区域拖动窗口，不改变播放状态；全屏时不可拖动。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("自动隐藏")) {
                LabeledContent(L("播放 / 暂停提示"), value: L("中央显示 1 秒"))
                LabeledContent(L("倍速提示"), value: L("调速后显示 1 秒"))
                LabeledContent(L("全屏控制栏"), value: L("鼠标移动后显示 2 秒"))
                Text(L("鼠标停在控制栏上或正在操作按钮、滑块时，控制栏保持显示。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearancePanel: some View {
        Form {
            Section {
                Picker(L("主题"), selection: Binding(get: { appearanceController.selection }, set: { appearanceController.select($0) })) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(L("默认为深色模式。选择跟随系统后，外观会随 macOS 自动切换。"))
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text(L("外观")).font(.title2.bold())
            }
            Text(L("主题应用于播放器和 Settings；视频画面及其黑边保持原样。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("快捷键与操作")).font(.title2.bold())
                    Text(L("在播放器窗口中使用以下操作。"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            GroupBox(L("文件与播放")) {
                VStack(spacing: 12) {
                    row(L("打开文件"), "⌘ O")
                    row(L("新建播放窗口"), "⌘ N", note: L("需要在 General 开启允许多个播放窗口"))
                    row(L("播放 / 暂停"), L("空格"), note: L("也可单击播放区域或播放 / 暂停按钮；失焦点击行为见 General"))
                    row(L("停止并回到开头"), L("停止按钮"))
                    row(L("窗口置顶 / 取消置顶"), L("图钉按钮"), note: L("选中时保持置顶；暂停或停止后仍保持，关闭图钉即可取消"))
                    row(L("拖入文件播放"), L("拖放到播放区域"), note: L("支持从 Finder 拖入本地视频或音频，替换当前文件并自动播放"))
                    row(L("切换全屏"), "⌃ ⌘ F", note: L("也可双击播放区域或点击全屏按钮"))
                    row(L("退出全屏"), "Esc")
                    row(L("移动窗口"), L("按住播放区域拖动"), note: L("播放或暂停、聚焦或失焦均可；仅普通窗口模式，拖动不改变播放状态"))
                }.padding(10)
            }
            GroupBox(L("跳转与音量")) {
                VStack(spacing: 12) {
                    row(L("快退") + " / " + L("快进") + " \(seekStepSeconds) " + L("秒"), "← / →")
                    row(L("增大 / 减小音量"), "↑ / ↓", note: L("方向键每次调整 5%；滚轮方向可在 General 中设置，默认向上减小、向下增大"))
                    row(L("跳转到指定时间"), L("点击或拖动进度条"), note: L("操作时在滑块上方显示目标时间"))
                }.padding(10)
            }
            GroupBox(L("播放速度")) {
                VStack(spacing: 12) {
                    row(L("加速 0.25×"), "A")
                    row(L("减速 0.25×"), "S")
                    Text(L("范围 0.25×–4×；暂停时也可调整，下次播放时生效。左上角提示在调速 1 秒后隐藏。"))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10)
            }
            Text("⌃ Control    ⌘ Command    ·    Settings：⌘ ,")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity)
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
