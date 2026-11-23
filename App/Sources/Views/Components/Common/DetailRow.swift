import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DetailRow: View {
    var name: String
    var value: String
    var body: some View {
        HStack {
            Text(name).foregroundStyle(MokoTheme.secondaryInk)
            Spacer()
            Text(value).font(.system(.body, design: .default)).monospacedDigit().textSelection(
                .enabled
            ).lineLimit(1)
        }.padding(.vertical, 4)
    }
}
