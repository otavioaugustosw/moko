import SwiftUI

@available(macOS 26.0, *)
struct OnboardingFeatures: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("php, postgresql and mariadb, already on this mac").font(.system(size: 28, weight: .semibold))
            Image("MokoMascot").resizable().scaledToFit().frame(height: 85).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 16) {
                feature(
                    "php web server", icon: "chevron.left.forwardslash.chevron.right",
                    description: "serve your project locally")
                feature(
                    "sql servers", icon: "globe",
                    description: "postgresql and mariadb included")
                feature(
                    "database editor", icon: "tablecells",
                    description: "browse tables and run sql")
            }.frame(maxWidth: 950)
        }
    }
    private func feature(_ title: String, icon: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(MokoTheme.selectionInk)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(description).font(.callout).foregroundStyle(MokoTheme.secondaryInk).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity).frame(height: 148)
            .foregroundStyle(MokoTheme.ink).background(MokoTheme.featureSurface, in: RoundedRectangle(cornerRadius: 20))
    }
}
