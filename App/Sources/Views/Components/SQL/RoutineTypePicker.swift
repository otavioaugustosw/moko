import SwiftUI

struct RoutineTypePicker: View {
    @Binding var type: String
    var label = "type"
    var engine: DatabaseEngine = .mariadb
    private var choices: [String] {
        engine.isPostgreSQL ? PostgreSQLSQL.types + ["void", "trigger", "record"] : RoutineSQLType.choices
    }
    @State private var custom = false
    var body: some View {
        HStack(spacing: 4) {
            Picker(
                "",
                selection: Binding(
                    get: {
                        choices.contains(RoutineSQLType.name(type)) ? RoutineSQLType.name(type) : "custom"
                    },
                    set: {
                        if $0 == "custom" { custom = true } else { type = RoutineSQLType.selecting($0, current: type) }
                    })
            ) {
                ForEach(choices, id: \.self) { Text($0).tag($0) }
                Text("custom…").tag("custom")
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(
                label).accessibilityIdentifier(label)
            if !RoutineSQLType.defaultSize(RoutineSQLType.name(type)).isEmpty {
                TextField(
                    RoutineSQLType.defaultSize(RoutineSQLType.name(type)),
                    text: Binding(
                        get: { RoutineSQLType.size(type) }, set: { type = RoutineSQLType.resizing($0, current: type) })
                )
                .textFieldStyle(.roundedBorder).frame(width: 62)
                .accessibilityLabel(label + " size or precision").help("length, or precision and scale")
            }
        }.popover(isPresented: $custom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("custom sql type").font(.headline)
                TextField("e.g. datetime(6)", text: $type).textFieldStyle(.roundedBorder).accessibilityLabel(
                    "custom sql type")
                Button("done") { custom = false }.buttonStyle(MokoButtonStyle(prominent: true)).keyboardShortcut(
                    .defaultAction)
            }.padding(16).frame(width: 280)
        }
    }
}
