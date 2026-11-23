import SwiftUI

@available(macOS 26.0, *)
struct PostgreSQLColumnEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: DatabaseModel
    @State var draft: PostgreSQLColumnDraft
    @State private var error = ""
    @State private var review = false
    private var types: [String] { Array(Set(PostgreSQLSQL.types + [draft.type])).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.original == nil ? "new column" : "edit column").font(.title2.weight(.semibold))
            Form {
                TextField("name", text: $draft.name)
                Picker("type", selection: $draft.type) { ForEach(types, id: \.self) { Text($0).tag($0) } }
                    .disabled(draft.generated)
                TextField("size or precision", text: $draft.size).disabled(draft.generated || !draft.hasSize)
                Toggle("allow null", isOn: $draft.nullable).disabled(draft.primary || draft.generated)
                Picker("identity", selection: $draft.identity) {
                    Text("none").tag("none")
                    Text("by default").tag("by default")
                    Text("always").tag("always")
                }.disabled(draft.generated || !["smallint", "integer", "int", "bigint"].contains(draft.type))
                TextField("default SQL expression", text: $draft.defaultSQL).disabled(
                    draft.generated || draft.identity != "none")
                TextField("comment", text: $draft.comment)
            }
            TransientNotice($error, isError: true)
            TransientNotice($browser.error, isError: true)
            HStack {
                Button("cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("save") {
                    if draft.original != nil && draft.originalType != draft.declaration {
                        review = true
                    } else {
                        save()
                    }
                }.buttonStyle(MokoButtonStyle(prominent: true))
            }.disabled(browser.busy)
        }.padding(24).frame(width: 540).foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
            .buttonStyle(MokoButtonStyle()).interactiveDismissDisabled(browser.busy)
            .onChange(of: draft.type) { _, value in
                if !draft.hasSize { draft.size = "" }
                if !["smallint", "integer", "int", "bigint"].contains(value) { draft.identity = "none" }
            }
            .sheet(isPresented: $review) {
                DestructiveReview(
                    title: "change column type?",
                    message: "existing values may be converted or rejected. keep a backup.",
                    actionTitle: "change type", cancel: { review = false },
                    confirm: {
                        review = false
                        save()
                    })
            }
    }
    private func save() {
        do {
            let plan = try draft.plan(location: browser.location, table: browser.table)
            browser.apply(plan) { if $0 { dismiss() } }
        } catch { self.error = error.localizedDescription }
    }
}

#if DEBUG
    #Preview("postgresql column") {
        PostgreSQLColumnEditor(browser: PreviewFixtures.browser(engine: .postgresql), draft: .init())
    }

#endif
