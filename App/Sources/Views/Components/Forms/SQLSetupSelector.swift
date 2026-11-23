import SwiftUI

struct SQLSetupChoice: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    static var all: [Self] {
        [
        .init(id: "postgresql", title: "postgresql", detail: "included · recommended", icon: "network"),
        .init(
            id: "bundled", title: "mariadb", detail: RuntimeComponents.included ? "included" : "optional download",
            icon: "externaldrive"),
        .init(id: "external", title: "existing server", detail: "connect to your server", icon: "link"),
        .init(id: "later", title: "set up later", detail: "choose from the panel", icon: "clock"),
        ]
    }
}

struct SQLSetupSelector: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
            ForEach(SQLSetupChoice.all) { choice in
                SQLSetupOption(choice: choice, selected: selection == choice.id) { selection = choice.id }
            }
        }.accessibilityIdentifier("sql-setup-options")
    }
}

private struct SQLSetupOption: View {
    let choice: SQLSetupChoice
    let selected: Bool
    let action: () -> Void
    @Environment(\.mokoReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: choice.icon).font(.system(size: 20, weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? MokoTheme.selectionInk : MokoTheme.secondaryInk)
                        .accessibilityHidden(true)
                }
                Text(choice.title).font(.headline)
                Text(choice.detail).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 84, alignment: .leading).padding(12)
                .foregroundStyle(MokoTheme.ink)
                .background(
                    selected ? MokoTheme.selectionInk.opacity(0.08) : MokoTheme.canvas,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? MokoTheme.selectionInk : MokoTheme.separator, lineWidth: selected ? 2 : 1))
        }.buttonStyle(SQLSetupOptionStyle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: selected)
            .accessibilityLabel(choice.title + ", " + choice.detail)
            .accessibilityValue(selected ? "selected" : "not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("sql-option." + choice.id)
    }
}

private struct SQLSetupOptionStyle: ButtonStyle {
    @Environment(\.mokoReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
    #Preview("sql setup choices") {
        @Previewable @State var selection = "postgresql"
        SQLSetupSelector(selection: $selection).padding(24).frame(width: 560).background(MokoTheme.surface)
    }
#endif
