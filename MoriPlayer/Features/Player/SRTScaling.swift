import Foundation

enum SRTScaling {
    static func ass(from source: String, percent: Int, aspect: Double = 16.0 / 9) throws -> String {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let expression = try NSRegularExpression(pattern: #"(?m)^\s*(\d+):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d+):(\d{2}):(\d{2})[,.](\d{3})[^\n]*\n([\s\S]*?)(?=\n\s*\n|\z)"#)
        let ns = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { throw NSError(domain: "Subtitles", code: 4, userInfo: [NSLocalizedDescriptionKey: L("未找到有效的 SRT 时间轴，无法调整字幕大小。")]) }
        let size = 36 * Double(percent) / 100
        let width = Int((720 * (aspect.isFinite && aspect > 0 ? aspect : 16.0 / 9)).rounded())
        var result = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(width)
        PlayResY: 720
        ScaledBorderAndShadow: yes
        WrapStyle: 0

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,PingFang SC,\(size),&H00FFFFFF,&H00FFFFFF,&H00000000,&HFF000000,0,0,0,0,100,100,0,0,1,2,0,2,30,30,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        for match in matches {
            func time(_ offset: Int) -> String {
                let values = (offset...offset + 3).map { Int(ns.substring(with: match.range(at: $0)))! }
                return String(format: "%d:%02d:%02d.%02d", values[0], values[1], values[2], values[3] / 10)
            }
            var body = ns.substring(with: match.range(at: 9)).trimmingCharacters(in: .whitespacesAndNewlines)
            body = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")
            for tag in ["b", "i", "u"] {
                body = body.replacingOccurrences(of: "<" + tag + ">", with: "{\\" + tag + "1}", options: .caseInsensitive)
                body = body.replacingOccurrences(of: "</" + tag + ">", with: "{\\" + tag + "0}", options: .caseInsensitive)
            }
            body = body.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            body = body.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
                body = body.replacingOccurrences(of: entity, with: value)
            }
            body = body.replacingOccurrences(of: "\n", with: "\\N")
            result += "Dialogue: 0,\(time(1)),\(time(5)),Default,,0,0,0,,\(body)\n"
        }
        return result
    }
}
