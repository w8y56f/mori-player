import SwiftUI

// Read the app preference without changing macOS or Foundation's global language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .chinese: "中文"
        case .english: "English"
        }
    }
    static func resolved(_ value: String?, preferred: [String] = Locale.preferredLanguages) -> String {
        switch AppLanguage(rawValue: value ?? "system") ?? .system {
        case .chinese: "zh-Hans"
        case .english: "en"
        case .system: preferred.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
}

func L(_ key: String) -> String {
    let language = AppLanguage.resolved(UserDefaults.standard.string(forKey: "appLanguage"))
    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
}

/// Native menu headings are outside the SwiftUI view hierarchy.
@MainActor final class LanguageMenuController: NSObject {
    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(update), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(update), name: NSApplication.didFinishLaunchingNotification, object: nil)
        center.addObserver(self, selector: #selector(update), name: NSMenu.didBeginTrackingNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func update() { Self.synchronize() }
    static func synchronize() {
        guard let menu = NSApp.mainMenu else { return }
        let pairs = [("File", "文件"), ("Edit", "编辑"), ("View", "显示"), ("Window", "窗口"), ("Help", "帮助"), ("Settings…", "设置…"), ("About Mori Player", "关于 Mori Player"), ("Quit Mori Player", "退出 Mori Player"), ("Hide Mori Player", "隐藏 Mori Player"), ("Hide Others", "隐藏其他"), ("Show All", "全部显示"), ("Undo", "撤销"), ("Redo", "重做"), ("Cut", "剪切"), ("Copy", "复制"), ("Paste", "粘贴"), ("Select All", "全选"), ("Minimize", "最小化"), ("Zoom", "缩放"), ("Close Window", "关闭窗口"), ("Bring All to Front", "前置全部窗口")]
        let chinese = AppLanguage.resolved(UserDefaults.standard.string(forKey:"appLanguage")) == "zh-Hans"
        func apply(_ menu: NSMenu) {
            for item in menu.items {
                if let pair = pairs.first(where: { item.title == $0.0 || item.title == $0.1 }) { item.title = chinese ? pair.1 : pair.0; item.submenu?.title = item.title }
                if let submenu = item.submenu { apply(submenu) }
            }
        }
        apply(menu)
    }
}
