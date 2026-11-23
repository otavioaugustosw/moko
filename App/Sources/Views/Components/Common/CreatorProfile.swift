import SwiftUI

struct CreatorProfile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("CreatorPortrait").resizable().scaledToFit().accessibilityLabel("portrait of otávio augusto")
            Text("otávio augusto, 2026").font(.callout).italic()
            Text("digital image, png technique").font(.caption2).italic()
                .foregroundStyle(MokoTheme.secondaryInk)
            Text(
                """
                i'm a developer who loves design, music, and fashion. i built moko because great development tools shouldn't be complicated or... unavailable on macos.
                """
            )
            .font(.callout).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }.padding(.horizontal, 4).padding(.top, 8)
    }
}
