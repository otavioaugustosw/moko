import SwiftUI

struct OptionalMariaDBCard: View {
    var port = "13306"
    let install: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("mariadb server").font(.headline).foregroundStyle(MokoTheme.secondaryInk)
            TrafficLight(state: .red, width: 165).saturation(0).opacity(0.22).accessibilityHidden(true)
            Text("not installed").font(.system(size: 20, weight: .semibold))
            Button("install mariadb", systemImage: "plus", action: install).buttonStyle(MokoButtonStyle())
            Divider().overlay(MokoTheme.separator)
            DetailRow(name: "address", value: "127.0.0.1:" + port)
            DetailRow(name: "component", value: "optional")
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 385, alignment: .topLeading).padding(20)
            .foregroundStyle(MokoTheme.ink).background(
                MokoTheme.surface.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(MokoTheme.secondaryInk.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .accessibilityElement(children: .contain).accessibilityIdentifier("mariadb-placeholder")
    }
}

#if DEBUG
    #Preview("mariadb · not installed") { OptionalMariaDBCard(install: {}).padding().frame(width: 390, height: 470) }
#endif
