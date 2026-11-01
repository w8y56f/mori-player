# Mori Player

English | [简体中文](README.md)

A native macOS local media player built with Swift, SwiftUI, AppKit and embedded VLCKit. Mori means “forest”; the green icon combines trees with a play symbol, matching the minimal interface.

<img src="MoriPlayer/Resources/Assets.xcassets/AppMark.imageset/AppMark.png" width="128" alt="Mori Player forest and play icon" />

Current version: **0.1.0**. Minimum system version: **macOS 14.0**.

## Features

- Local video and audio playback with an embedded VLC engine. No separate VLC installation or conversion is required. Actual files tested include AVI, WMV, RM, RMVB, MKV, MP4, MOV, FLV and MPG. Compatibility depends on codecs, file integrity and access permissions.
- Play, pause, stop, click/drag seeking, remaining time, volume and native full screen. A target-time bubble appears while seeking.
- Configurable backward/forward step: **1–60 seconds**, **5 seconds** by default. Button numbers follow the setting; relative seeks show a centered 1-second indicator.
- **0.25×–4×** playback speed in 0.25× steps, with a top-left indicator that hides after 1 second. Play/pause actions also have centered indicators.
- Drop video or audio from Finder to play it. Drag the video area to move a window in windowed mode.
- Pin the window on top. The selected pin remains green when inactive; other controls become gray.
- Full-screen controls overlay the bottom of the video and hide 2 seconds after mouse movement, remaining visible while hovered or operated.
- Independent player windows and native macOS tabs. Closing one tab leaves other players running.
- Remembered playback positions and volume by default, with an optional fixed initial volume.
- Dark (default), Light and System themes. Interface languages: Follow System (default), Chinese and English.

## Subtitles

The subtitle button sits to the left of volume. Load files, select embedded or external tracks, disable subtitles and choose text encoding. You can also drop a subtitle onto the video without changing the playback position or pause state.

- **Automatic discovery:** same-directory SRT, ASS and SSA files, matching the exact basename first, then recognized language suffixes with Chinese preferred. Unrelated names and subdirectories are not scanned. Disable discovery in General.
- **Manual formats:** SRT, ASS, SSA, VTT, SMI, SUB and IDX. Bitmap IDX/SUB subtitles require both matching files. Actual compatibility depends on file contents.
- **Encoding:** automatic BOM, UTF-8, GB18030 and Big5 detection, with manual overrides. Conversion uses temporary copies and never modifies the source.
- **Size:** external SRT supports 50–200% in 10% steps, reset to 100%, and a remembered preference. Other formats and embedded tracks show an unavailable explanation.
- **Baseline style:** SRT is converted to temporary ASS. At 100%, the script uses a 720-high coordinate system, 36-point PingFang SC, white text with a black outline, transparent background and bottom alignment. Timing, line breaks and basic bold/italic/underline are preserved. Text burned into video cannot be adjusted separately.
- **Feedback:** manually loading and enabling a track shows “Subtitles loaded” and its filename; reusing a loaded track shows “Subtitles enabled.” The hint lasts 1.5 seconds. Automatic discovery, size and encoding changes remain silent.

The app is sandboxed. If subtitles beside the video cannot be read, choose “Allow Access to Subtitle Folder…” from the subtitle button and select the directory. A security-scoped bookmark remembers the grant. Companion bitmap subtitle files also require read access.

## Settings

Open **Mori Player → Settings… (⌘,)**.

| Location | Options |
| --- | --- |
| General → Language | Follow System (default), 中文, English. Applied immediately and saved. A Chinese preferred system language selects Chinese; other languages use English. Some system file-panel labels follow macOS language. |
| General → Windows | One player window by default; optionally allow multiple windows. Closing the last player quits the app and Settings by default. Disable to keep the app in the Dock. |
| General → Initial window size | Fit to screen (default), remember last size, or original video size. Manual resizing is retained for subsequent videos in that window. |
| General → Play | Seek step, playback position history and automatic subtitle loading. |
| General → Initial volume | Remember the last level, including mute; first-use volume is 70%. Alternatively use a fixed initial value. New windows use it; existing windows remain independent. |
| General → Mouse controls | The first click on an inactive video only activates the window by default; the next click plays/pauses. Wheel direction can be reversed. |
| Appearance | Dark (default), Light, System. Video and letterboxing retain their original appearance. |
| Shortcuts & Controls | Operation reference, including the configured seek interval. |
| About | App version, build-time Git identity and Powered by Stone Wang. The app menu’s About command opens this same page. |

## Keyboard and mouse

Shortcuts apply to the current player window. `⌘` means Command; `⌃` means Control.

| Action | Keyboard | Mouse |
| --- | --- | --- |
| Open file | `⌘O` | Welcome button or File menu |
| New player window | `⌘N` | File menu; requires multiple windows |
| Play / pause | `Space` | Click the video or play button |
| Seek backward / forward | `←` / `→` | Control-bar buttons; uses the configured step |
| Stop and return to start | — | Stop button |
| Volume | `↑` / `↓`, 5% per press | Slider; wheel defaults to up decreasing and down increasing, with reversal available |
| Speed up / slow down | `A` / `S`, 0.25× per press | — |
| Seek to a time | — | Click or drag the seek bar |
| Toggle full screen | `⌃⌘F`; `Esc` to exit | Double-click the video or use the full-screen button |
| Pin on top | — | Pin next to Stop |
| Move window | — | Drag the video or letterboxing in windowed mode, playing or paused, active or inactive |
| Load subtitles | — | Drop onto the video or use the subtitle button |

Single-click handling waits for the system double-click interval to avoid pausing while entering full screen. Moving the window does not change playback state.

## Build and run

Requires Xcode, Swift 6 and a network connection for the initial dependency download. The deployment target is macOS 14.0; development validation has used Apple Silicon. Intel Macs and macOS 14 have not been verified on hardware.

Prepare pinned **VLCKit 3.7.3** first. The script downloads from VideoLAN, verifies SHA-256 and stores artifacts under the ignored `.build/Dependencies` directory:

```sh
sh Scripts/PrepareDependencies.sh
```

Use this consistent **Release** path for everyday builds:

```sh
xcodebuild -project MoriPlayer.xcodeproj \
  -scheme MoriPlayer -configuration Release \
  -derivedDataPath .build/DerivedData build

open ".build/DerivedData/Build/Products/Release/Mori Player.app"
```

For debugging, prepare dependencies, open `MoriPlayer.xcodeproj`, select the `MoriPlayer` scheme and My Mac, then press `⌘R`. Debug and Release are separate products: building one does not update the other. Fully quit an old process before opening a new build.

The project currently uses local ad hoc signing. Configure developer signing, notarization and the Bundle Identifier before distribution. Frameworks and license notices are embedded; see [VLCKit LICENSE](MoriPlayer/ThirdParty/VLCKit-LICENSE.txt) and [VideoLAN VLCKit](https://github.com/videolan/vlckit) for source and release information.

## Version and persistence

An About example is `0.1.0 (abc1234 - dirty)`. The parentheses contain the build-time short Git commit ID; `dirty` denotes uncommitted changes. Rebuild after a clean commit to display `0.1.0 (abc1234)`. Unavailable Git metadata appears as `unknown`.

The build script generates and embeds `BuildMetadata.json` without rewriting tracked source. Git is not required at runtime. A commit requires a new build to update the displayed identity; an already running process keeps its original metadata.

Preferences, volume and playback history use persistent `UserDefaults` in the app sandbox, not temporary files. Positions are checkpointed every 5 seconds and on pause, seek, file replacement and close, with up to 200 files retained. Records are checked against path, size, modification time and duration. Moving or renaming a file creates a new identity; Stop or completion clears its resume point. Unexpected termination may lose progress since the last checkpoint.

## Validation

Test videos are not distributed with the repository and should not be committed. Pass your own local files to the real decoding probe:

```sh
sh Scripts/TestVideoFormats.sh "/path/to/video.mkv" "/path/to/video.avi"
```

It checks decoded video/audio, displayed frames and basic playback controls. Subtitle integration checks require a test MKV with a same-basename GB18030 SRT:

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

Metadata and language checks:

```sh
python3 Tests/BuildMetadataTests.py
swiftc -swift-version 6 -parse-as-library \
  MoriPlayer/App/Language.swift Tests/LanguageTests.swift -o .build/language-tests
.build/language-tests ".build/DerivedData/Build/Products/Release/Mori Player.app/Contents/Resources"
```

`Tests/` also contains window, appearance and history checks. Some older AVPlayer-specific cases still require VLC migration and are not evidence for the current engine. The commands above cover only the listed tests, not the entire directory.

Manual acceptance should cover actual Finder drops, subtitle rendering and sound, sandbox authorization and restoration after restart, language changes during playback, theme changes, full screen, multiple windows and repeated native tab closure. Decode counts do not replace visual and listening checks.

## Structure and scope

```text
MoriPlayer/App/               Entry point, windows, language, appearance and build info
MoriPlayer/Features/Player/   Playback, input, controls, subtitles and feedback
MoriPlayer/Features/Settings/ Settings and About
MoriPlayer/Resources/         Icons and Chinese/English localization
MoriPlayer/ThirdParty/        Third-party licenses
Config/                      Document types and sandbox configuration
Scripts/                     Dependencies, packaging, build metadata and test tools
Tests/                       Standalone Swift/Python regression checks
```

The current focus is local playback. A playlist, network streaming UI and subtitle editor are not implemented. Bitmap subtitles and text burned into video do not support text font-size adjustment.
