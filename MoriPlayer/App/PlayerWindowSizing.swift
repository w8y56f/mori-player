import AppKit

/// This preference affects initial sizing, not the user's subsequent resizing.
enum InitialWindowSizeMode: String, CaseIterable, Identifiable {
    case smart, remember, native
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: L("智能适配屏幕")
        case .remember: L("记住上次窗口大小")
        case .native: L("按视频原始尺寸适配")
        }
    }

    static func read(from preferences: UserDefaults) -> Self {
        Self(rawValue: preferences.string(forKey: "initialWindowSizeMode") ?? "smart") ?? .smart
    }
}

enum PlayerWindowSizing {
    static let defaultContentSize = CGSize(width: 1040, height: 650)
    static let minimumContentSize = CGSize(width: 800, height: 400)

    static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    static func rememberedSize(in preferences: UserDefaults) -> CGSize? {
        guard let values = preferences.dictionary(forKey: "rememberedPlayerContentSize"),
              let width = values["width"] as? Double, let height = values["height"] as? Double else { return nil }
        let size = CGSize(width: width, height: height)
        return isValid(size) ? size : nil
    }

    static func saveContentSize(_ size: CGSize, in preferences: UserDefaults) {
        guard isValid(size) else { return }
        preferences.set(["width": size.width, "height": size.height], forKey: "rememberedPlayerContentSize")
    }

    static func constrain(_ size: CGSize, minimum: CGSize, maximum: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, minimum.width), maximum.width),
               height: min(max(size.height, minimum.height), maximum.height))
    }

    /// video is an aspect-ratio size for Smart, and a backing-converted point
    /// size for Native. chrome includes everything outside the actual video area.
    static func fittedVideoFrame(video: CGSize, chrome: CGSize, visible: CGSize,
                                 minimumFrame: CGSize, native: Bool) -> CGSize {
        guard isValid(video), isValid(visible) else {
            return constrain(defaultContentSize, minimum: minimumFrame, maximum: visible)
        }
        let limit = native ? visible : CGSize(width: visible.width * 0.75, height: visible.height * 0.8)
        var scale = min(max(1, limit.width - chrome.width) / video.width,
                        max(1, limit.height - chrome.height) / video.height)
        if native { scale = min(1, scale) }
        let target = CGSize(width: video.width * scale + chrome.width,
                            height: video.height * scale + chrome.height)
        return constrain(target, minimum: minimumFrame, maximum: visible)
    }

    static func boundedFrame(size: CGSize, topLeft: CGPoint, visible: CGRect) -> CGRect {
        let bounded = CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        return CGRect(x: min(max(topLeft.x, visible.minX), visible.maxX - bounded.width),
                      y: min(max(topLeft.y - bounded.height, visible.minY), visible.maxY - bounded.height),
                      width: bounded.width, height: bounded.height)
    }
}
