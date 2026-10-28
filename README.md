# Mori Player

[English](README.en.md) | 简体中文

一款使用 Swift、SwiftUI 与 AVFoundation 构建的原生 macOS 本地播放器。Mori（森）以简洁的森林绿图标和清爽的播放界面，让注意力回到影像本身。

<img src="MoriPlayer/Resources/Assets.xcassets/AppMark.imageset/AppMark.png" width="128" alt="Mori Player：森林与播放三角" />

## 功能

- 打开本地视频或音频，自动开始播放；支持播放、暂停、停止和跳转。
- 底部控制栏从左到右：快退 5 秒、播放 / 暂停、快进 5 秒、停止、已播放时间 / 总时长、播放进度条、剩余时间、音量滑块、全屏按钮。暂不提供播放列表。
- 拖动进度条定位；播放结束后再次播放会从头开始。
- 支持 0.25×–4× 倍速，步长 0.25×；非正常速度会在播放区域显示。
- 原生全屏、鼠标操作与键盘快捷键；Settings 中按类别展示完整操作说明。
- 沙盒文件访问：通过系统文件选择器取得用户选择文件的只读权限。

## 快捷键与鼠标操作

快捷键在播放器窗口内生效。点击菜单 **Mori Player → Settings…**（`⌘,`）查看操作面板。

| 操作 | 键盘 | 鼠标 |
| --- | --- | --- |
| 打开文件 | `⌘O` | 欢迎页“打开文件…”或 File 菜单 |
| 播放 / 暂停 | `空格` | 单击播放区域或播放 / 暂停按钮 |
| 快退 / 快进 5 秒 | `←` / `→` | 对应控制栏按钮 |
| 停止并回到开头 | — | 停止按钮 |
| 切换全屏 | `⌃⌘F` | 双击播放区域或点击全屏按钮 |
| 退出全屏 | `Esc` | 全屏按钮 |
| 增大 / 减小音量 | `↑` / `↓`，每次 5% | 播放区域内滚轮向上 / 向下，或拖动音量滑块 |
| 加速 / 减速 0.25× | `A` / `S` | — |
| 跳转到指定时间 | — | 拖动播放进度条 |

`⌘` 表示 Command，`⌃` 表示 Control。播放区域的单击会等待系统双击间隔，以避免双击全屏时意外暂停。

## 运行与构建

最低部署版本为 macOS 14.0，使用 Swift 6。验证环境为 Xcode 26.6、Swift 6.3.3、Apple Silicon；尚未在 macOS 14 或 Intel Mac 实机验证。没有第三方依赖。

打开 `MoriPlayer.xcodeproj`，选择 `MoriPlayer` scheme 和 `My Mac`，按 `⌘R`。也可执行：

```sh
xcodebuild -project MoriPlayer.xcodeproj \
  -scheme MoriPlayer \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
```

应用位于 `.build/DerivedData/Build/Products/Debug/Mori Player.app`。项目使用本地 ad hoc 签名；分发前需配置正式 Bundle Identifier、开发者签名和公证。

## 验证

下面的集成检查会生成本地音频文件，使用真实 AVPlayer 验证载入、播放 / 暂停、前后跳转、停止、音量与倍速边界、结束后重播、损坏文件和快速切换文件：

```sh
mkdir -p .build
swiftc -swift-version 6 -parse-as-library \
  MoriPlayer/Features/Player/PlayerModel.swift Tests/PlayerSmokeTests.swift \
  -o .build/player-smoke-tests
.build/player-smoke-tests
```

## 项目结构

```text
MoriPlayer/
├── App/                   # 入口、菜单和 Settings 场景
├── Features/
│   ├── Player/            # 播放状态、视频视图、控制栏和输入处理
│   └── Settings/          # 快捷键与操作说明面板
└── Resources/             # 图标和主题色
Scripts/GenerateIcon.swift # 可重复运行的 AppKit 矢量图标生成脚本
Tests/PlayerSmokeTests.swift
```

重新生成图标：`swift Scripts/GenerateIcon.swift`。Xcode 自动同步 `MoriPlayer/` 中的源码和资源。

## 当前范围

播放能力取决于 macOS 原生解码器，具体兼容性取决于容器和编解码组合，不保证支持所有 MKV、AVI 等媒体文件。当前未接入 VLCKit，也未实现播放列表、字幕选择、网络串流或播放记录。当前界面依据文字描述实现，尚未与参考截图核对。
