import SwiftUI

struct AppearancePicker: View {
    @Binding var selection: String
    private let choices = ["system", "light", "dark"]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    selection = choice
                } label: {
                    Text(choice).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(selection == choice ? MokoTheme.onAccent : MokoTheme.ink)
                        .background(
                            selection == choice ? MokoTheme.accent : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel(choice)
                    .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }.padding(4).background(MokoTheme.sidebar, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain).accessibilityLabel("appearance")
    }
}
