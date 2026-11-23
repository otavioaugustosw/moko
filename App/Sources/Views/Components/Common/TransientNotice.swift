import SwiftUI

struct TransientNotice: View {
    let text: String
    var isError = false
    var dismiss: () -> Void = {}
    @Environment(\.mokoReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var hovering = false
    @State private var displayedText = ""
    init(text: String, isError: Bool = false, dismiss: @escaping () -> Void = {}) {
        self.text = text
        self.isError = isError
        self.dismiss = dismiss
    }
    init(_ value: Binding<String>, isError: Bool = false) {
        let text = value.wrappedValue
        self.init(text: text, isError: isError) {
            if !text.isEmpty && value.wrappedValue == text { value.wrappedValue = "" }
        }
    }
    init(text: String, isError: Bool = false, dismissMatching: @escaping (String) -> Void) {
        self.init(text: text, isError: isError) { dismissMatching(text) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if visible && !displayedText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                    Text(displayedText.asLabel).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("dismiss", systemImage: "xmark") {
                        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) { visible = false }
                        dismiss()
                    }.labelStyle(.iconOnly)
                        .buttonStyle(.plain).help("dismiss notification")
                }.font(.callout).foregroundStyle(isError ? MokoTheme.errorInk : MokoTheme.ink)
                    .padding(12).background(MokoTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .onHover { hovering = $0 }.padding(.bottom, 8).transition(.opacity)
            }
        }.task(id: text) {
            if !text.isEmpty { displayedText = text }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { visible = !text.isEmpty }
            guard !text.isEmpty else { return }
            do {
                try await Task.sleep(for: .seconds(isError ? 10 : 5))
                while hovering { try await Task.sleep(for: .milliseconds(200)) }
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) { visible = false }
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                dismiss()
            } catch { return }
        }.onDisappear {
            // View removal can occur during reconciliation; clear feedback on the next main cycle.
            DispatchQueue.main.async(execute: dismiss)
        }
    }
}

extension String {
    /// A single short sentence is shown as a label, without its closing period.
    var asLabel: String {
        guard hasSuffix("."), !hasSuffix(".."), !dropLast().contains(". ") else { return self }
        return String(dropLast())
    }
}
