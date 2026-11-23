import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct DatabaseConfirmation: View {
    let plan: SQLPlan
    @ObservedObject var browser: DatabaseModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(plan.title).font(.title2.weight(.semibold))
            if !plan.summary.isEmpty {
                Text(plan.summary).font(.callout).textSelection(.enabled).lineLimit(3)
            }
            Text("deleted data cannot be recovered").font(.callout)
                .foregroundStyle(MokoTheme.secondaryInk)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel", role: .cancel, action: close)
                    .buttonStyle(MokoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(
                        browser.busy)
                Spacer()
                if browser.busy { ProgressView().controlSize(.small) }
                Button("delete", role: .destructive) { browser.apply(plan) { if $0 { close() } } }
                    .buttonStyle(MokoButtonStyle(destructive: true))
                    .disabled(browser.busy)
            }
        }.padding(24).frame(width: 440).foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
            .onAppear { browser.error = "" }.interactiveDismissDisabled(browser.busy)
            .onExitCommand { if !browser.busy { close() } }
    }
}
