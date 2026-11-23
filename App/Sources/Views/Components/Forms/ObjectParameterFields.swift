import SwiftUI

struct ObjectParameterFields: View {
    @Binding var parameters: [NewDatabaseObjectDraft.Parameter]
    let procedure: Bool
    var engine: DatabaseEngine = .mariadb
    @State private var page = 0
    private let pageSize = 3
    private var pages: Int { max(1, (parameters.count + pageSize - 1) / pageSize) }
    private var visibleParameters: [NewDatabaseObjectDraft.Parameter] {
        Array(parameters.dropFirst(page * pageSize).prefix(pageSize))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("parameters (\(parameters.count))").font(.callout.weight(.semibold))
                Spacer()
                Button("add parameter", systemImage: "plus", action: addParameter)
            }
            if parameters.isEmpty {
                Text("no parameters").font(.callout).foregroundStyle(MokoTheme.secondaryInk)
            } else {
                HStack(spacing: 8) {
                    Text("name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("type · size").frame(width: 164, alignment: .leading)
                    if procedure { Text("direction").frame(width: 66, alignment: .leading) }
                    Color.clear.frame(width: 34, height: 1)
                }.font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                ForEach(visibleParameters) { parameter in row(parameter) }
                if pages > 1 {
                    HStack {
                        Text(
                            "\(page * pageSize + 1)–\(min(parameters.count, (page + 1) * pageSize)) of \(parameters.count)"
                        )
                        .font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                        Spacer()
                        Button("previous parameters", systemImage: "chevron.left") { page -= 1 }
                            .labelStyle(.iconOnly).disabled(page == 0)
                        Text("\(page + 1)/\(pages)").font(.caption.monospacedDigit())
                        Button("next parameters", systemImage: "chevron.right") { page += 1 }
                            .labelStyle(.iconOnly).disabled(page + 1 >= pages)
                    }
                }
            }
        }.onChange(of: parameters.count) { page = min(page, pages - 1) }
    }
    private func row(_ original: NewDatabaseObjectDraft.Parameter) -> some View {
        let value = Binding(
            get: { parameters.first { $0.id == original.id } ?? original },
            set: { updated in
                if let index = parameters.firstIndex(where: { $0.id == original.id }) { parameters[index] = updated }
            })
        return HStack(spacing: 8) {
            TextField("e.g. amount", text: value.name).textFieldStyle(.roundedBorder).accessibilityLabel(
                "parameter name")
            RoutineTypePicker(type: value.type, label: "parameter type", engine: engine).frame(width: 164)
            if procedure {
                Picker("direction", selection: value.mode) {
                    ForEach(["IN", "OUT", "INOUT"], id: \.self) { Text($0.lowercased()).tag($0) }
                }.labelsHidden().frame(width: 66)
            }
            Button("remove parameter", systemImage: "trash", role: .destructive) {
                parameters.removeAll { $0.id == original.id }
            }.labelStyle(.iconOnly)
        }.frame(height: 34)
    }
    private func addParameter() {
        let names = Set(parameters.map { $0.name.lowercased() })
        var number = parameters.count + 1
        while names.contains("parameter\(number)") { number += 1 }
        parameters.append(.init(name: "parameter\(number)", type: engine.isPostgreSQL ? "integer" : "int"))
        page = (parameters.count - 1) / pageSize
    }
}
