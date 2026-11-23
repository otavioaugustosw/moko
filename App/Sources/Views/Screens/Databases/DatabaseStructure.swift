import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension DatabaseWorkspace {

    var structure: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("new column") {
                    if browser.engine.isPostgreSQL {
                        postgresColumn = .init()
                        return
                    }
                    columnEditor = .init(
                        original: nil, name: "", definition: "varchar(255) DEFAULT NULL")
                }
                Button("edit column") {
                    if browser.engine.isPostgreSQL,
                        let column = browser.columns.first(where: { $0.name == selectedColumn }) {
                        postgresColumn = .init(column: column)
                        return
                    }
                    if let selectedColumn,
                        let definition = DatabaseSQL.columnDefinition(
                            selectedColumn, ddl: browser.ddl) {
                        columnEditor = .init(
                            original: selectedColumn, name: selectedColumn, definition: definition)
                    }
                }.disabled(selectedColumn == nil)
                Button("new index or constraint") { newConstraint = true }
                Menu {
                    Button("delete column", role: .destructive) {
                        if let selectedColumn {
                            plan = .init(
                                title: "delete column",
                                sql:
                                    "ALTER TABLE \(browser.qualifiedTable) DROP COLUMN \(browser.identifier(selectedColumn));",
                                database: browser.database, destructive: true,
                                summary: browser.database + "." + browser.table + " · "
                                    + selectedColumn)
                        }
                    }.disabled(selectedColumn == nil)
                    Button("change table attributes") {
                        browser.tab = "sql"
                        browser.sql =
                            (browser.engine.isPostgreSQL
                                ? "ALTER TABLE \(browser.qualifiedTable) SET (fillfactor = 100);"
                                : "ALTER TABLE \(browser.qualifiedTable)\n  ENGINE = \(browser.selectedTable?.engine.isEmpty == false ? browser.selectedTable!.engine : "InnoDB");")
                    }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("more structure actions")
                }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize().tint(MokoTheme.ink)
            }.buttonStyle(MokoButtonStyle()).disabled(browser.busy || !browser.writable)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("column").frame(width: 125, alignment: .leading)
                        Text("type and attributes").frame(width: 240, alignment: .leading)
                        Text("default").frame(width: 140, alignment: .leading)
                        Text("collation").frame(width: 150, alignment: .leading)
                    }.font(.caption.weight(.semibold)).padding(8).background(.quaternary.opacity(0.3))
                    ForEach(browser.columns) { column in
                        Button {
                            selectedColumn = column.name
                        } label: {
                            HStack(alignment: .top) {
                                Text(column.name).frame(width: 125, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(column.type)
                                    Text(
                                        [
                                            column.nullable ? "null" : "not null",
                                            column.key.lowercased(), column.extra.lowercased(),
                                        ].filter { !$0.isEmpty }.joined(separator: " · ")
                                    ).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                    if !column.comment.isEmpty {
                                        Text(column.comment).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                    }
                                }.frame(width: 240, alignment: .leading)
                                Text(column.defaultValue ?? "—").frame(
                                    width: 140, alignment: .leading)
                                Text(column.collation.isEmpty ? "—" : column.collation).frame(
                                    width: 150, alignment: .leading)
                            }.font(.system(.callout, design: .monospaced)).padding(8).background(
                                column.name == selectedColumn
                                    ? MokoTheme.accent.opacity(0.16) : .clear
                            ).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(column.name == selectedColumn ? .isSelected : [])
                        Divider()
                    }
                }
            }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 8))
            if browser.engine.isPostgreSQL {
                PostgreSQLStructureObjects(browser: browser, plan: $plan)
            }
            DisclosureGroup("indexes") {
                if let indexes = browser.indexes { SQLGrid(result: indexes).frame(height: 180) }
            }
            DisclosureGroup("foreign keys") {
                if let keys = browser.foreignKeys { SQLGrid(result: keys).frame(height: 160) }
            }
            DisclosureGroup("create table") {
                ScrollView([.horizontal, .vertical]) {
                    Text(browser.ddl).font(.system(.caption, design: .monospaced)).textSelection(
                        .enabled
                    ).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }.frame(height: 220)
            }
        }
    }
}
