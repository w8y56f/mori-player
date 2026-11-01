# Mori Player

简体中文 | [English](README.en.md)

一款使用 Swift、SwiftUI、AppKit 和内置 VLCKit 构建的 macOS 本地播放器。Mori（森）的森林绿图标结合树林与播放三角，界面保持简洁。

<img src="MoriPlayer/Resources/Assets.xcassets/AppMark.imageset/AppMark.png" width="128" alt="Mori Player 森林播放图标" />

当前版本：**0.1.0**。最低系统版本：**macOS 14.0**。

## 功能

- 播放本地视频和音频；内置 VLC 内核，无需另外安装 VLC 或预先转码。已用实际文件验证 AVI、WMV、RM、RMVB、MKV，以及 MP4、MOV、FLV、MPG。兼容性取决于具体编码、文件完整性及访问权限。
- 播放、暂停、停止、点击／拖动进度条、剩余时间、音量及原生全屏。进度条操作时显示目标时间。
- 快进／快退步长可设为 **1～60 秒**，默认 **5 秒**；按钮数字和提示跟随设置，跳转时中央显示 1 秒提醒。
- **0.25×～4×** 倍速，每次调整 0.25×；左上角显示当前速度，1 秒后隐藏。播放／暂停也有中央提示。
- 从 Finder 拖入视频或音频即可播放；普通窗口下可按住播放区域拖动窗口。
- 可切换窗口置顶。置顶图钉在失焦时保持绿色，其他控制柔和变灰。
- 全屏控制栏覆盖在视频底部，鼠标移动后显示 2 秒；悬停或操作时保持显示。
- 支持独立多窗口及 macOS 原生标签页，关闭一个标签页不影响其他播放器。
- 默认记住播放位置和上次音量；可选固定初始音量。
- 深色（默认）、浅色、跟随系统三种主题；界面语言支持跟随系统（默认）、中文、English。

## 字幕

字幕按钮位于控制栏音量左侧，可加载、选择内嵌或外挂轨道、关闭字幕及选择编码。也可以直接将字幕文件拖入视频区域；加载不会改变播放位置或暂停状态。

- **自动匹配**：默认查找视频同目录的同名 SRT、ASS、SSA，其次匹配语言后缀，优先中文；不扫描子目录，不匹配无关文件名。General 中可关闭自动加载。
- **手动格式**：SRT、ASS、SSA、VTT、SMI、SUB、IDX。IDX/SUB 图像字幕需要同名配套文件；具体兼容性取决于文件内容。
- **编码**：自动识别 BOM、UTF-8、GB18030、Big5，也可手动指定。转换使用临时副本，不修改原文件。
- **大小**：外挂 SRT 支持 50%～200% 缩放，每次 10%，可恢复 100%，并记住选择。其他格式和内嵌轨道暂不支持，菜单会说明原因。
- **基准样式**：SRT 转为临时 ASS；100% 为 720 高度字幕坐标系、36 号 PingFang SC、白字黑描边、透明背景、底部居中。保留时间轴、换行及基本粗体、斜体、下划线。视频中已经压制的文字无法单独调整。
- **加载反馈**：手动加载并启用成功后，中央显示“已加载字幕”和文件名；重复使用已加载轨道显示“已启用字幕”。提示持续 1.5 秒；自动加载、字号和编码调整不弹出成功提示。

应用启用了沙盒。若不能自动读取视频旁的字幕，从字幕按钮选择“允许访问字幕所在文件夹…”，选择对应目录；授权以安全书签保存。图像字幕的配套文件也需要读取权限。

## 设置

通过 **Mori Player → Settings…（⌘,）** 打开设置。

| 位置 | 配置 |
| --- | --- |
| General → 语言 | 跟随系统、中文、English；立即生效并保存。系统首选语言为中文时使用中文，其他语言使用英文。部分系统文件面板文案遵循 macOS 语言。 |
| General → 窗口 | 默认单窗口，可允许多个窗口；默认关闭最后一个播放窗口时彻底退出，包括 Settings。可关闭此策略，让应用留在 Dock。 |
| General → 初始大小 | 智能适配屏幕（默认）、记住上次窗口大小、按视频原始尺寸适配。手动调整后，同一窗口后续视频保留该大小。 |
| General → 播放 | 快进／快退步长、记住播放位置、自动加载字幕。 |
| General → 初始音量 | 默认记住上次音量，包括静音；首次 70%。也可指定固定初始音量，新窗口采用该值，已有窗口独立。 |
| General → 鼠标操作 | 默认首次点击失焦播放区域仅激活窗口；下一次点击才播放／暂停。滚轮方向可反转。 |
| 外观 | Dark（默认）、Light、跟随系统。视频与黑边不受主题影响。 |
| 快捷键与操作 | 完整操作说明，跳转秒数随设置更新。 |
| 关于 | 软件版本、构建时 Git 信息、Powered by Stone Wang。菜单中的“关于 Mori Player”也打开此页。 |

## 快捷键与鼠标

快捷键作用于当前播放器窗口。`⌘` 为 Command，`⌃` 为 Control。

| 操作 | 键盘 | 鼠标 |
| --- | --- | --- |
| 打开文件 | `⌘O` | 欢迎页打开按钮或文件菜单 |
| 新建播放窗口 | `⌘N` | 文件菜单；需允许多个窗口 |
| 播放／暂停 | `空格` | 单击视频或播放按钮 |
| 快退／快进 | `←` / `→` | 控制栏按钮；使用配置步长 |
| 停止并回到开头 | — | 停止按钮 |
| 音量 | `↑` / `↓`，每次 5% | 音量滑块；滚轮默认向上减小、向下增大，可反转 |
| 加速／减速 | `A` / `S`，每次 0.25× | — |
| 定位进度 | — | 点击或拖动进度条 |
| 全屏／退出全屏 | `⌃⌘F`；`Esc` 退出 | 双击视频或全屏按钮 |
| 置顶 | — | 停止按钮右侧图钉 |
| 移动窗口 | — | 普通窗口下按住视频或黑边拖动，播放／暂停及聚焦／失焦时均适用 |
| 加载字幕 | — | 将字幕拖到视频区域，或使用字幕按钮 |

单击会等待系统双击间隔，以避免双击全屏时顺带暂停。拖动窗口不改变播放状态。

## 构建和运行

需要 Xcode、Swift 6 及网络连接（首次下载依赖）。工程的部署目标为 macOS 14.0；开发验证环境为 Apple Silicon。尚未在 Intel Mac 或 macOS 14 实机验收。

先准备固定版本 **VLCKit 3.7.3**。脚本从 VideoLAN 官方下载并核对 SHA-256，产物保存在被 Git 忽略的 `.build/Dependencies`：

```sh
sh Scripts/PrepareDependencies.sh
```

日常交付统一使用以下 **Release** 路径：

```sh
xcodebuild -project MoriPlayer.xcodeproj \
  -scheme MoriPlayer -configuration Release \
  -derivedDataPath .build/DerivedData build

open ".build/DerivedData/Build/Products/Release/Mori Player.app"
```

也可在准备依赖后打开 `MoriPlayer.xcodeproj`，选择 `MoriPlayer` scheme 和 My Mac，按 `⌘R` 开发调试。Debug 与 Release 是独立产物，构建其中一个不会更新另一个；打开新版前应完全退出旧进程。

当前使用本地 ad hoc 签名，正式分发前需配置开发者签名、公证及 Bundle Identifier。依赖框架和许可证随应用打包；相关许可见 [VLCKit LICENSE](MoriPlayer/ThirdParty/VLCKit-LICENSE.txt)，源码与发行信息见 [VideoLAN VLCKit](https://github.com/videolan/vlckit)。

## 版本与数据

关于页示例：`0.1.0 (abc1234 - dirty)`。括号内为构建时 Git 短 commit ID；存在未提交改动时追加 `dirty`。干净提交后重新构建会显示 `0.1.0 (abc1234)`。Git 不可用时显示 `unknown`。

构建脚本生成并打包 `BuildMetadata.json`，不改写源码；运行应用时无需 Git。提交后需要重新构建，正在运行的旧进程不会自动获得新版本信息。

设置、音量及播放位置通过 `UserDefaults` 保存在应用沙盒的持久配置中，不是临时文件。播放位置每 5 秒及暂停、跳转、切换文件、关闭时保存，最多保留 200 个文件；按路径、大小、修改时间和时长核对。改名或移动文件视为新文件，停止或播放完成会清除续播点。异常退出可能损失最近一次保存后的进度。

## 验证

测试视频不随仓库分发，也不应提交。可将自己的本地文件传给实际解码检查：

```sh
sh Scripts/TestVideoFormats.sh "/path/to/video.mkv" "/path/to/video.avi"
```

此检查读取实际视频／音频解码与显示帧数，并检查基本播放控制。字幕集成检查需要一份带同名 GB18030 SRT 的测试 MKV：

```sh
mkdir -p .build/FormatTests .build/Frameworks
ln -sfn ../Dependencies/VLCKit.framework .build/Frameworks/VLCKit.framework

for test in SubtitleTests SubtitleScaleTests SubtitleFeedbackTests SeekStepTests; do
  swiftc -swift-version 6 -parse-as-library \
    -F .build/Dependencies -framework VLCKit \
    MoriPlayer/App/Language.swift \
    MoriPlayer/Features/Player/PlayerModel.swift \
    MoriPlayer/Features/Player/Subtitles.swift \
    MoriPlayer/Features/Player/SRTScaling.swift \
    MoriPlayer/Features/Player/PlayerSurface.swift \
    "Tests/$test.swift" -o ".build/FormatTests/$test"
  ".build/FormatTests/$test" "/path/to/test-video.mkv"
done
```

元数据与语言检查：

```sh
python3 Tests/BuildMetadataTests.py
swiftc -swift-version 6 -parse-as-library \
  MoriPlayer/App/Language.swift Tests/LanguageTests.swift -o .build/language-tests
.build/language-tests ".build/DerivedData/Build/Products/Release/Mori Player.app/Contents/Resources"
```

`Tests/` 还包含窗口、外观、历史记录等回归用例；部分早期 AVPlayer 专用用例尚未完成 VLC 适配，不应将其视为当前内核的验收依据。上面的命令只覆盖所列测试，不代表整个目录全部通过。

手动验收重点：Finder 实际拖放、字幕画面与声音、沙盒授权及重启恢复、播放中切换语言、主题切换、全屏、多窗口及反复关闭原生标签页。自动解码检查不能代替听感和画面观感验收。

## 项目结构与范围

```text
MoriPlayer/App/               应用入口、窗口、语言、外观及版本信息
MoriPlayer/Features/Player/   播放状态、输入、控制栏、字幕与提示
MoriPlayer/Features/Settings/ 设置与关于页
MoriPlayer/Resources/         图标及中英文资源
MoriPlayer/ThirdParty/        第三方许可证
Config/                      文档类型和沙盒配置
Scripts/                     依赖准备、打包、版本元数据及测试脚本
Tests/                       独立 Swift/Python 回归检查
```

目前以本地文件播放为主，尚未提供播放列表、网络串流界面或字幕编辑器。图片字幕及已经压入画面的文字不支持文字字号调整。

## GitHub Release 发布

项目级发布技能见 [mori-release](.agents/skills/mori-release/SKILL.md)。在 Codex 中可明确调用 `$mori-release`，例如“使用 $mori-release 将当前版本发布到 GitHub Release”。技能先显示 Git 工作区及上游同步状态；有未提交改动时询问提交并推送，只有未推送提交时询问推送，完成后再打包发布。

`python3 Scripts/Release.py status` 只检查本地状态。`package` 要求干净且已推送的提交，构建 universal arm64/x86_64 Release 并生成 `.build/releases/v<版本>/MoriPlayer-<版本>-macOS.dmg`、`SHA256SUMS.txt` 及本地清单。DMG 中包含应用、Applications 快捷方式和安装说明。

`publish --notes <中英文说明文件>` 按版本创建 GitHub Release，上传 DMG 和校验文件，已有版本不覆盖。当前 ad hoc 构建必须明确使用 `--allow-unnotarized`，并作为未公证预发布提供；正式公证构建需在 `package` 时传入现有 Developer ID、Team ID 和钥匙串 notarytool 配置。凭据不存入仓库。创建 skill 不会自动提交、推送或发布。
