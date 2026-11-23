import SwiftUI

struct PostgreSQLStructureObjects: View {
    @ObservedObject var browser: DatabaseModel
    @Binding var plan: SQLPlan?
    @State private var renamed: StructureObject?
    @State private var newName = ""
    private struct StructureObject: Identifiable {
        var id: String { kind + ":" + name }
        let name: String
        let kind: String
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let constraints = browser.constraints {
                Text("constraints").font(.headline)
                ForEach(constraints.rows.indices, id: \.self) { row in
                    objectRow(
                        name: constraints.text(row, 0) ?? "", kind: "constraint",
                        definition: (constraints.text(row, 1) ?? "") + " · " + (constraints.text(row, 2) ?? ""))
                }
            }
            if let indexes = browser.indexes {
                Text("independent indexes").font(.headline)
                ForEach(indexes.rows.indices, id: \.self) { row in
                    if indexes.text(row, 4) != "t" {
                        objectRow(
                            name: indexes.text(row, 0) ?? "", kind: "index", definition: indexes.text(row, 1) ?? "")
                    }
                }
            }
        }.disabled(browser.busy || !browser.writable)
            .sheet(item: $renamed) { object in
                VStack(alignment: .leading, spacing: 16) {
                    Text("rename " + object.kind).font(.title2.weight(.semibold))
                    TextField("name", text: $newName).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("cancel") { renamed = nil }
                        Spacer()
                        Button("rename") { rename(object) }.buttonStyle(MokoButtonStyle(prominent: true))
                            .disabled(newName.isEmpty || newName.utf8.count > 63 || newName.contains("\0"))
                    }
                }.padding(24).frame(width: 460).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
                    .buttonStyle(MokoButtonStyle())
            }
    }
    private func objectRow(name: String, kind: String, definition: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.callout.weight(.semibold))
                Text(definition).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MokoTheme.secondaryInk).textSelection(.enabled)
            }
            Spacer()
            Menu {
                Button("rename") {
                    newName = name
                    renamed = .init(name: name, kind: kind)
                }
                Button("delete", role: .destructive) {
                    let sql =
                        kind == "index"
                        ? "DROP INDEX " + browser.qualified(name)
                        : "ALTER TABLE " + browser.qualifiedTable + " DROP CONSTRAINT " + browser.identifier(name)
                    plan = .init(
                        title: "delete " + kind, sql: sql, database: browser.database, destructive: true,
                        summary: name + " · dependent objects are preserved; no cascade is used")
                }
            } label: {
                Image(systemName: "ellipsis").accessibilityLabel("more actions")
            }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize()
        }.padding(12).background(MokoTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private func rename(_ object: StructureObject) {
        let sql =
            object.kind == "index"
            ? "ALTER INDEX " + browser.qualified(object.name) + " RENAME TO " + browser.identifier(newName)
            : "ALTER TABLE " + browser.qualifiedTable + " RENAME CONSTRAINT " + browser.identifier(object.name) + " TO "
                + browser.identifier(newName)
        browser.apply(.init(title: "rename " + object.kind, sql: sql, database: browser.database, statements: [sql])) {
            if $0 { renamed = nil }
        }
    }
}
