import SwiftUI

struct NewDatabaseObjectView: View {
    @ObservedObject var library: DatabaseObjectLibrary
    let tables: [DatabaseTable]
    @State var draft: NewDatabaseObjectDraft
    let close: () -> Void
    @State private var error = ""
    @State private var confirming = false
    private var needsBody: Bool {
        !library.engine.isPostgreSQL || ![DatabaseObjectKind.schema, .sequence, .trigger].contains(draft.kind)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("new " + draft.kind.rawValue).font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 20) {
                details.frame(width: 250)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if draft.kind.callable {
                        ObjectParameterFields(
                            parameters: $draft.parameters, procedure: draft.kind == .procedure || library.engine.isPostgreSQL,
                            engine: library.engine)
                    }
                    if needsBody {
                        Text(draft.kind == .view ? "select query" : "sql body").font(.callout.weight(.semibold))
                        SQLBodyEditor(text: $draft.body, parameters: draft.parameters.map(\.name)).disabled(!needsBody)
                            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MokoTheme.separator, lineWidth: 1))
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 4) {
                                    TransientNotice($error, isError: true)
                                    TransientNotice(
                                        text: library.error, isError: true, dismissMatching: library.dismissError)
                                }.padding(8)
                            }
                    } else {
                        EmptyView()
                        TransientNotice($error, isError: true)
                        TransientNotice(text: library.error, isError: true, dismissMatching: library.dismissError)
                    }
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Button("cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if library.busy { ProgressView().controlSize(.small) }
                Button("create") { if draft.kind == .event && draft.enabled { confirming = true } else { save() } }
                    .buttonStyle(MokoButtonStyle(prominent: true)).disabled(
                        draft.name.isEmpty || (needsBody && draft.body.isEmpty))
            }
        }.padding(24).frame(width: 820, height: 580).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
            .tint(MokoTheme.selectionInk).buttonStyle(MokoButtonStyle()).disabled(library.busy)
            .interactiveDismissDisabled(library.busy)
            .onAppear { if library.engine.isPostgreSQL && draft.returns == "int" { draft.returns = "integer" } }
            .sheet(isPresented: $confirming) {
                DestructiveReview(
                    title: "enable scheduled execution?",
                    message: "this event can run its SQL body automatically when the server scheduler is on.",
                    actionTitle: "create and enable", cancel: { confirming = false },
                    confirm: {
                        confirming = false
                        save()
                    })
            }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            ObjectField("name") {
                TextField("e.g. calculate_total", text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel(
                    "object name")
            }
            if draft.kind.callable { routineFields }
            if draft.kind == .trigger { triggerFields }
            if draft.kind == .sequence {
                ObjectField("start") { TextField("1", text: $draft.sequenceStart).textFieldStyle(.roundedBorder) }
                ObjectField("increment") {
                    TextField("1", text: $draft.sequenceIncrement).textFieldStyle(.roundedBorder)
                }
                Toggle("cycle", isOn: $draft.sequenceCycle).toggleStyle(.switch)
            }
            if draft.kind == .event {
                ObjectField("schedule") {
                    TextField("EVERY 1 DAY", text: $draft.schedule).textFieldStyle(.roundedBorder).accessibilityLabel(
                        "schedule")
                }
                Toggle("enable this event", isOn: $draft.enabled).toggleStyle(.switch)
                ObjectField("comment") { commentField }
            }
        }
    }
    private var commentField: some View {
        TextField("optional comment", text: $draft.comment).textFieldStyle(.roundedBorder).accessibilityLabel("comment")
    }
    private var routineFields: some View {
        Group {
            if draft.kind == .function {
                ObjectField("return type") {
                    RoutineTypePicker(type: $draft.returns, label: "return type", engine: library.engine)
                }
                if !library.engine.isPostgreSQL {
                    Toggle("deterministic", isOn: $draft.deterministic)
                        .toggleStyle(.switch)
                        .help("the same input always produces the same result")
                }
            }
            ObjectField("security") {
                Picker("security", selection: $draft.security) {
                    Text("invoker").tag("INVOKER")
                    Text("definer").tag("DEFINER")
                }.labelsHidden().help(
                    "invoker uses the calling account's permissions; definer uses the creator's permissions")
            }
            if library.engine.isPostgreSQL {
                ObjectField("language") {
                    Picker("language", selection: $draft.language) {
                        Text("plpgsql").tag("plpgsql")
                        Text("sql").tag("sql")
                    }.labelsHidden()
                }
                ObjectField("volatility") {
                    Picker("volatility", selection: $draft.volatility) {
                        ForEach(["VOLATILE", "STABLE", "IMMUTABLE"], id: \.self) { Text($0.lowercased()).tag($0) }
                    }.labelsHidden()
                }
            } else {
                ObjectField("data access") {
                    Picker("data access", selection: $draft.access) {
                        ForEach(["CONTAINS SQL", "NO SQL", "READS SQL DATA", "MODIFIES SQL DATA"], id: \.self) {
                            Text($0.lowercased()).tag($0)
                        }
                    }.labelsHidden()
                }
            }
            ObjectField("comment") { commentField }
        }
    }
    private var triggerFields: some View {
        Group {
            ObjectField("table") {
                Picker("table", selection: $draft.table) {
                    Text("choose a table").tag("")
                    ForEach(tables.filter { !$0.isView }) { Text($0.name).tag($0.name) }
                }.labelsHidden()
            }
            if library.engine.isPostgreSQL {
                ObjectField("function") {
                    Picker("function", selection: $draft.triggerFunction) {
                        Text("choose trigger function").tag("")
                        ForEach(
                            library.items.filter {
                                $0.kind == .function && $0.resultType == "trigger" && $0.signature.isEmpty
                            }
                        ) { Text($0.name).tag($0.name) }
                    }.labelsHidden()
                }
            }
            ObjectField("timing") {
                Picker("timing", selection: $draft.timing) {
                    Text("before").tag("BEFORE")
                    Text("after").tag("AFTER")
                }
                .labelsHidden()
            }
            ObjectField("event") {
                Picker("event", selection: $draft.triggerEvent) {
                    ForEach(["INSERT", "UPDATE", "DELETE"], id: \.self) { Text($0.lowercased()).tag($0) }
                }.labelsHidden()
            }
        }
    }
    private func save() {
        error = ""
        do { try library.create(draft) { if $0 { close() } } } catch { self.error = error.localizedDescription }
    }
}
