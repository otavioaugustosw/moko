import SwiftUI

struct DestructiveReview: View {
    let title: String
    let message: String
    var actionTitle = "apply changes"
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(MokoTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("cancel", role: .cancel, action: cancel)
                    .buttonStyle(MokoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                Spacer()
                Button(actionTitle, role: .destructive, action: confirm).buttonStyle(MokoButtonStyle(destructive: true))
            }
        }.padding(24).frame(width: 460).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
            .onExitCommand(perform: cancel)
    }
}
