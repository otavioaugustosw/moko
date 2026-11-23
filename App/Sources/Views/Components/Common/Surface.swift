import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Surface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
            MokoTheme.surface,
            in: RoundedRectangle(cornerRadius: 20)
        ).overlay(RoundedRectangle(cornerRadius: 20).stroke(MokoTheme.separator, lineWidth: 1))
            .tint(MokoTheme.selectionInk)
    }
}
