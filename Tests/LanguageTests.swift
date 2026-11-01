import Foundation
@main struct LanguageTests {
 static func main() {
  precondition(AppLanguage.resolved(nil, preferred:["zh-TW"]) == "zh-Hans")
  precondition(AppLanguage.resolved("system", preferred:["en-US"]) == "en")
  precondition(AppLanguage.resolved("system", preferred:["ja-JP"]) == "en")
  precondition(AppLanguage.resolved("system", preferred:[]) == "en")
  precondition(AppLanguage.resolved("en", preferred:["zh-Hans"]) == "en")
  precondition(AppLanguage.resolved("zh-Hans", preferred:["en"]) == "zh-Hans")
  precondition(AppLanguage.resolved("invalid", preferred:["en"]) == "en")
  let root = URL(fileURLWithPath:CommandLine.arguments[1])
  let english = NSDictionary(contentsOf:root.appendingPathComponent("en.lproj/Localizable.strings")) as! [String:String]
  let chinese = NSDictionary(contentsOf:root.appendingPathComponent("zh-Hans.lproj/Localizable.strings")) as! [String:String]
  precondition(english.keys.sorted() == chinese.keys.sorted())
  precondition(english["语言"] == "Language" && chinese["语言"] == "语言")
  precondition(english["已加载字幕"] == "Subtitles loaded")
  precondition(english.values.allSatisfy { !$0.isEmpty })
  print("PASS: system/explicit/fallback resolution and \(english.count) matching translations")
 }
}
