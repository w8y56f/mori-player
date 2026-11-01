import Foundation

@main
struct BuildInfoTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MoriBuildInfo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        for (index, test) in [
            ("abc1234", true as Bool?, "0.0.1 (abc1234 - dirty)"),
            ("abc1234", false, "0.0.1 (abc1234)"),
            ("no-commit", true, "0.0.1 (no-commit - dirty)"),
            ("unknown", nil, "0.0.1 (unknown)")
        ].enumerated() {
            let bundleURL = directory.appendingPathComponent("Case\(index).bundle")
            let contents = bundleURL.appendingPathComponent("Contents")
            let resources = contents.appendingPathComponent("Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleDisplayName": "Mori Player", "CFBundleName": "MoriPlayer",
                "CFBundleIdentifier": "test.mori.buildinfo.\(index)", "CFBundlePackageType": "BNDL",
                "CFBundleShortVersionString": "0.0.1"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            let metadata: [String: Any] = ["commit": test.0, "dirty": test.1.map { $0 as Any } ?? NSNull()]
            try JSONSerialization.data(withJSONObject: metadata).write(to: resources.appendingPathComponent("BuildMetadata.json"))
            let bundle = Bundle(url: bundleURL)!
            let result = AppBuildInfo.read(from: bundle)
            precondition(result.name == "Mori Player")
            precondition(result.versionDescription == test.2)
            // A missing or corrupt generated resource must degrade safely.
            try Data("invalid".utf8).write(to: resources.appendingPathComponent("BuildMetadata.json"))
            precondition(AppBuildInfo.read(from: bundle).versionDescription == "0.0.1 (unknown)")
        }
        print("PASS: bundled name/version, dirty and clean formatting, no-commit/unknown metadata, corrupt-resource fallback.")
    }
}
