import SwiftUI

struct MokoButtonStyle: ButtonStyle {
    var prominent = false
    var inverted = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    private var height: CGFloat {
        switch size {
        case .mini: 26
        case .small: 30
        case .large, .extraLarge: 44
        default: 34
        }
    }
    private func fill(isDestructive: Bool) -> Color {
        if isDestructive { return .clear }
        if !prominent { return MokoTheme.surface }
        if !enabled { return Color("DisabledAccent") }
        return inverted ? MokoTheme.onAccent : MokoTheme.accent
    }
    private func ink(isDestructive: Bool) -> Color {
        if isDestructive { return enabled ? MokoTheme.errorInk : MokoTheme.secondaryInk }
        if prominent { return enabled && inverted ? MokoTheme.accent : MokoTheme.onAccent }
        return enabled ? MokoTheme.ink : MokoTheme.secondaryInk
    }
    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = destructive || configuration.role == .destructive
        return configuration.label.font(.system(size: height >= 44 ? 15 : 13, weight: .medium))
            .lineLimit(1).foregroundStyle(ink(isDestructive: isDestructive)).padding(.horizontal, 12)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(fill(isDestructive: isDestructive), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(
                    prominent || isDestructive ? .clear : MokoTheme.separator, lineWidth: 1)
            )
            .brightness(configuration.isPressed && enabled ? -0.06 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
