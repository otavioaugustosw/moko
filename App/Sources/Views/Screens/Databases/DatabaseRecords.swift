import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension DatabaseWorkspace {

    var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    rowDraft = browser.draft(row: nil)
                } label: {
                    Image(systemName: "plus")
                }.help("add row").accessibilityLabel("add row").disabled(!browser.writable)
                Button("edit") {
                    if let selectedRow { rowDraft = browser.draft(row: selectedRow) }
                }.disabled(!browser.rowEditable || selectedRow == nil)
                Button {
                    do {
                        if let selectedRow, browser.data?.cells.indices.contains(selectedRow) == true {
                            plan = try browser.rowPlan(browser.draft(row: selectedRow), deleting: true)
                        }
                    } catch { formError = error.localizedDescription }
                } label: {
                    Image(systemName: "trash")
                }.help("delete row").accessibilityLabel("delete row").disabled(!browser.rowEditable || selectedRow == nil)
                Spacer()
                RefreshClock(browser: browser)
                Picker("automatic refresh", selection: $browser.refreshInterval) {
                    Text("automatic: off").tag(0)
                    Text("every 5 seconds").tag(5)
                    Text("every 10 seconds").tag(10)
                }.pickerStyle(.menu).labelsHidden().fixedSize().help(
                    "pauses while editing or when the window is hidden"
                ).accessibilityLabel("automatic refresh")
                Button {
                    export(browser.data, filename: browser.table)
                } label: {
                    Image(systemName: "arrow.up.document")
                }.help("export page as csv").accessibilityLabel("export page as csv").disabled(browser.data == nil)
                Button {
                    browser.loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("refresh rows now, automatic refresh follows the selected interval")
                .accessibilityLabel("refresh rows")
            }.buttonStyle(MokoButtonStyle()).disabled(browser.busy)
            HStack {
                Text("where").font(.system(.caption, design: .monospaced)).foregroundStyle(
                    MokoTheme.secondaryInk)
                TextField("e.g. id > 10", text: $browser.filter).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("where filter")
                    .font(.system(.caption, design: .monospaced)).onSubmit {
                        browser.offset = 0
                        browser.loadData()
                    }
                Button("filter") {
                    browser.offset = 0
                    browser.loadData()
                }.disabled(browser.busy)
            }
            if let data = browser.data {
                recordsGrid(data).frame(minHeight: 180, maxHeight: .infinity)
                HStack {
                    Text(pageDescription(data)).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                    Spacer()
                    Button {
                        browser.offset = max(0, browser.offset - browser.pageSize)
                        browser.loadData()
                    } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(browser.offset == 0 || browser.busy).help("previous page").accessibilityLabel("previous page")
                    Button {
                        browser.offset += browser.pageSize
                        browser.loadData()
                    } label: {
                        Image(systemName: "chevron.right")
                    }.disabled(
                        data.rows.count <= browser.pageSize || browser.busy || data.truncated
                    ).help("next page").accessibilityLabel("next page")
                }
            }
        }
    }

    private func pageDescription(_ data: SQLResult) -> String {
        let count = min(data.rows.count, browser.pageSize), page = browser.offset / browser.pageSize + 1
        if count == 0 { return "0 rows · page \(page)" }
        let range = "rows \(browser.offset + 1)–\(browser.offset + count)"
        if data.rows.count <= browser.pageSize && !data.truncated { return range + " · page \(page) of \(page)" }
        return range + " · page \(page) · more rows available"
    }

    func recordsGrid(_ data: SQLResult) -> SQLGrid {
        let database = browser.database, table = browser.table, columns = browser.columns,
            connection = browser.connection
        let keys = browser.foreignKeys
        let commit: (Int, Int, String, @escaping (Bool) -> Void) -> Void = { row, column, value, completed in
            do {
                formError = ""
                guard browser.connection == connection, browser.database == database,
                    browser.table == table, browser.columns == columns, browser.data == data,
                    columns.indices.contains(column), data.cells.indices.contains(row)
                else {
                    formError = "the table changed; reopen the field"
                    completed(false)
                    return
                }
                var draft = browser.draft(row: row)
                draft.values[columns[column].name] = .init(text: value, mode: .value)
                let generated = try browser.rowPlan(draft)
                browser.apply(generated, completed: completed)
            } catch {
                formError = error.localizedDescription
                completed(false)
            }
        }
        return SQLGrid(
            result: data, visibleLimit: browser.pageSize, selection: $selectedRow,
            doubleClick: { if browser.rowEditable { rowDraft = browser.draft(row: $0) } },
            sort: { field in
                browser.descending = browser.sortColumn == field ? !browser.descending : false
                browser.sortColumn = field
                browser.offset = 0
                browser.loadData()
            },
            canEditCell: { _, column in
                browser.rowEditable && !browser.busy && browser.columns.indices.contains(column)
                    && !browser.columns[column].generated
            },
            editCell: commit, editingChanged: { browser.setEditorVisible($0 || editing) },
            linkedColumn: { column in
                columns.indices.contains(column)
                    && keys?.rows.indices.contains(where: {
                        keys?.text($0, 1) == columns[column].name
                    }) == true
            },
            cellPopover: { row, column, editingCell, close in
                guard columns.indices.contains(column), data.cells.indices.contains(row),
                    browser.connection == connection, browser.database == database,
                    browser.table == table
                else { return nil }
                if editingCell, browser.rowEditable, let kind = columns[column].temporal,
                    !columns[column].generated {
                    return AnyView(
                        SQLTemporalEditor(
                            name: columns[column].name, kind: kind,
                            value: data.cells[row][column].text ?? "",
                            save: { value, completed in
                                if value == data.cells[row][column].text {
                                    completed(nil)
                                    return
                                }
                                commit(row, column, value) { success in
                                    completed(
                                        success
                                            ? nil
                                            : (browser.error.isEmpty ? formError : browser.error))
                                }
                            }, close: close))
                }
                if !editingCell, let connection,
                    let target = ForeignKeyTarget.make(
                        metadata: keys, columns: columns, row: data.cells[row], column: column, engine: browser.engine) {
                    return AnyView(
                        ForeignKeyPreview(target: target, connection: connection) {
                            guard browser.connection == connection, !browser.busy else { return }
                            close()
                            browser.openReference(target)
                        })
                }
                return nil
            })
    }
}
