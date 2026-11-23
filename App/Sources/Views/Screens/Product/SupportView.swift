import SwiftUI

@available(macOS 26.0, *)
struct SupportView: View {
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "cup.and.saucer").font(.system(size: 40)).foregroundStyle(MokoTheme.selectionInk)
                Text("buy me a coffee").font(.title2.weight(.semibold))
                Text("optional · every feature works without it").foregroundStyle(MokoTheme.secondaryInk)
                if let destination = URL(string: "https://buymeacoffee.com/otavioaugustosw") {
                    Link("buy me a coffee", destination: destination)
                        .buttonStyle(MokoButtonStyle(prominent: true))
                        .foregroundStyle(MokoTheme.onAccent)
                        .help("opens buy me a coffee in your browser")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
