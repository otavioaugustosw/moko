import SwiftUI

struct ObjectField<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(MokoTheme.secondaryInk)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
