import SwiftUI

struct AboutView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    private let build = AppBuildInfo.read()

    var body: some View {
        VStack(spacing: 16) {
            Image("AppMark")
                .resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(build.name)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(build.versionDescription)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Powered by Stone Wang")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
