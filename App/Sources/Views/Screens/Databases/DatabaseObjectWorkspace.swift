import AppKit
import SwiftUI

struct DatabaseObjectWorkspace: View {
    @ObservedObject var library: DatabaseObjectLibrary
    var viewData: (String) -> Void = { _ in }
    var feedbackVisible = true
    @State private var editedBody = ""
    @State private var editing = false
    @State private var review: Review?
    @State private var values: [Int: String] = [:]
    @State private var nulls: Set<Int> = []
    @State private var error = ""
    private enum Review: String, Identifiable {
        case replace, delete, execute, enableEvent, enableScheduler
        var id: String { rawValue }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let object = library.selected {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(object.name, systemImage: object.kind.symbol).font(.title3.weight(.semibold))
                            Text(library.database + " · " + object.kind.rawValue).foregroundStyle(
                                MokoTheme.secondaryInk)
                        }
                        Spacer()
                        Button("refresh", systemImage: "arrow.clockwise") { library.select(object) }
                        Button("delete", systemImage: "trash", role: .destructive) { review = .delete }.disabled(
                            !library.writable)
                    }
                    if object.kind == .event { eventControls(object) }
                    if [.view, .materializedView].contains(object.kind) {
                        Button("view data", systemImage: "tablecells") { viewData(object.name) }
                    }
                    if object.kind == .materializedView {
                        Button("refresh materialized view") { library.refreshMaterializedView() }.disabled(!library.writable)
                    }
                    if object.kind == .trigger && library.engine.isPostgreSQL {
                        Button(object.enabled ? "disable trigger" : "enable trigger") { library.setTriggerEnabled(!object.enabled) }
                            .disabled(!library.writable)
                    }
                    if let definition = library.definition {
                        definitionEditor(definition)
                        if object.kind.callable { invocation(definition) }
                    } else if library.busy {
                        ProgressView().accessibilityLabel("loading SQL object")
                    }
                }
                if feedbackVisible {
                    VStack(spacing: 0) {
                        TransientNotice(text: library.error, isError: true, dismissMatching: library.dismissError)
                        TransientNotice($error, isError: true)
                        TransientNotice(text: library.message, dismissMatching: library.dismissMessage)
                    }
                }
                ForEach(Array(library.results.enumerated()), id: \.offset) { _, result in
                    SQLGrid(result: result).frame(minHeight: 140, maxHeight: 280)
                }
            }
        }.buttonStyle(MokoButtonStyle()).disabled(library.busy)
            .onChange(of: library.selected?.id) {
                editing = false
                values = [:]
                nulls = []
                error = ""
            }
            .sheet(item: $review) { operation in
                DestructiveReview(
                    title: reviewTitle(operation), message: reviewMessage(operation),
                    actionTitle: reviewAction(operation), cancel: { review = nil },
                    confirm: {
                        review = nil
                        apply(operation)
                    })
            }
    }
    private func definitionEditor(_ definition: DatabaseObjectDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editing ? "edit sql body" : "definition").font(.headline)
                Spacer()
                Button("copy definition", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(definition.sql, forType: .string)
                }
                if !editing {
                    Button("edit body") {
                        editedBody = definition.body
                        editing = true
                    }.disabled(!library.editable)
                }
            }
            if editing {
                SQLBodyEditor(text: $editedBody, parameters: definition.parameters.map(\.name))
                    .frame(minHeight: 190, maxHeight: 290).padding(8).background(
                        MokoTheme.surface, in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityLabel("sql body")
                HStack {
                    Button("back") { editing = false }.buttonStyle(MokoButtonStyle(prominent: true))
                    Spacer()
                    Button("save") { review = .replace }.disabled(editedBody.isEmpty || editedBody == definition.body)
                }
            } else {
                Text(definition.sql).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(MokoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                if !library.editable && library.writable {
                    Text("edit this object in the sql tab").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                }
            }
        }
    }
    private func invocation(_ definition: DatabaseObjectDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("run " + definition.object.kind.rawValue).font(.headline)
            ForEach(definition.parameters) { parameter in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parameter.name).font(.callout.weight(.semibold))
                        Text(parameter.mode.lowercased() + " · " + parameter.type).font(.caption).foregroundStyle(
                            MokoTheme.secondaryInk)
                    }.frame(width: 140, alignment: .leading)
                    if parameter.input {
                        TextField(
                            "value",
                            text: Binding(
                                get: { values[parameter.ordinal] ?? "" },
                                set: { values[parameter.ordinal] = $0 })
                        )
                        .textFieldStyle(.roundedBorder).disabled(nulls.contains(parameter.ordinal))
                        .accessibilityLabel(parameter.name)
                        Toggle(
                            "null",
                            isOn: Binding(
                                get: { nulls.contains(parameter.ordinal) },
                                set: {
                                    if $0 { nulls.insert(parameter.ordinal) } else { nulls.remove(parameter.ordinal) }
                                })
                        ).toggleStyle(.switch).fixedSize()
                    } else {
                        Text("returned by the procedure").foregroundStyle(MokoTheme.secondaryInk)
                    }
                }
            }
            Button("run", systemImage: "play") { review = .execute }
        }.padding(16).background(MokoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func eventControls(_ object: DatabaseObject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(object.enabled ? "event enabled" : "event disabled")
                Button(object.enabled ? "disable event" : "enable event") {
                    if object.enabled { library.setEventEnabled(false) } else { review = .enableEvent }
                }
            }
            HStack {
                Text("scheduler: " + library.scheduler.lowercased()).foregroundStyle(MokoTheme.secondaryInk)
                Button(library.scheduler == "ON" ? "pause scheduler" : "start scheduler") {
                    if library.scheduler == "ON" {
                        library.setSchedulerEnabled(false)
                    } else {
                        review = .enableScheduler
                    }
                }.disabled(library.scheduler == "DISABLED")
            }
        }.font(.callout)
    }
    private func reviewTitle(_ operation: Review) -> String {
        switch operation {
        case .replace: "replace stored SQL body?"
        case .delete: "delete " + (library.selected?.kind.rawValue ?? "object") + "?"
        case .execute: "run this routine?"
        case .enableEvent: "enable this event?"
        case .enableScheduler: "start the event scheduler?"
        }
    }
    private func reviewMessage(_ operation: Review) -> String {
        switch operation {
        case .replace:
            "future calls or table changes will use the new SQL body. the original definition is retained if saving fails."
        case .delete:
            "this removes \(library.database).\(library.selected?.name ?? ""). export its definition first if you need to restore it."
        case .execute:
            "the routine runs with its declared permissions and can change data. "
                + "review the definition and parameter values before continuing."
        case .enableEvent:
            "the SQL body can run automatically according to its schedule when the server scheduler is on."
        case .enableScheduler: "this affects every enabled event on the server, across all databases."
        }
    }
    private func reviewAction(_ operation: Review) -> String {
        switch operation {
        case .replace: "replace body"
        case .delete: "delete"
        case .execute: "run"
        case .enableEvent: "enable event"
        case .enableScheduler: "start scheduler"
        }
    }
    private func apply(_ operation: Review) {
        do {
            switch operation {
            case .replace: try library.saveBody(editedBody) { if $0 { editing = false } }
            case .delete: library.deleteSelected { _ in }
            case .execute: library.run(values: values, nulls: nulls)
            case .enableEvent: library.setEventEnabled(true)
            case .enableScheduler: library.setSchedulerEnabled(true)
            }
        } catch { self.error = error.localizedDescription }
    }
}
