import Foundation

struct AppBuildInfo {
    let name: String
    let version: String
    let commit: String
    let isDirty: Bool?

    var versionDescription: String {
        "\(version) (\(commit)\(isDirty == true ? " - dirty" : ""))"
    }

    static func read(from bundle: Bundle = .main) -> AppBuildInfo {
        let info = bundle.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Mori Player"
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let metadata = bundle.url(forResource: "BuildMetadata", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(GitMetadata.self, from: $0) }
        return AppBuildInfo(name: name, version: version,
                            commit: metadata?.commit ?? "unknown", isDirty: metadata?.dirty)
    }

    private struct GitMetadata: Decodable {
        let commit: String
        let dirty: Bool?
    }
}
