import AppKit
import SwiftUI
import UniformTypeIdentifiers

// AppKit supports any number of result columns without rebuilding the SwiftUI table type.
struct SQLGrid: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let result: SQLResult
    var visibleLimit: Int = 500
    var selection: Binding<Int?> = .constant(nil)
    var doubleClick: ((Int) -> Void)?
    var sort: ((String) -> Void)?
    var canEditCell: ((Int, Int) -> Bool)?
    var editCell: ((Int, Int, String, @escaping (Bool) -> Void) -> Void)?
    var editingChanged: ((Bool) -> Void)?
    var linkedColumn: ((Int) -> Bool)?
    var cellPopover: ((Int, Int, Bool, @escaping () -> Void) -> AnyView?)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = DatabaseResultTable()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        context.coordinator.table = table
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.backgroundColor = MokoTheme.native("GridRow")
        table.gridColor = MokoTheme.native("Separator")
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = false
        table.clickedCell = { [weak coordinator = context.coordinator] row, column, count in
            coordinator?.clickedCell(row, column, count: count)
        }
        table.copySelection = { [weak coordinator = context.coordinator, weak table] in
            guard let coordinator, let table else { return }
            coordinator.copyRows(table)
        }
        let menu = NSMenu()
        let copy = NSMenuItem(
            title: "copy row", action: #selector(DatabaseResultTable.copy(_:)),
            keyEquivalent: "")
        copy.target = table
        menu.addItem(copy)
        table.menu = menu
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openRow)
        table.setAccessibilityLabel("sql result")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.backgroundColor = MokoTheme.native("GridRow")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        let changed =
            coordinator.parent.result != result || coordinator.parent.visibleLimit != visibleLimit
        let fieldsChanged = coordinator.parent.result.fields != result.fields,
            previousLimit = coordinator.parent.visibleLimit
        coordinator.parent = self
        let structureChanged = table.tableColumns.map(\.title) != result.fields.map(\.name)
        coordinator.suppressSelectionChanges = true
        defer { coordinator.suppressSelectionChanges = false }
        if structureChanged {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for (i, field) in result.fields.enumerated() {
                let column = NSTableColumn(identifier: .init(String(i)))
                column.title = field.name
                column.width = min(240, max(130, CGFloat(field.name.count * 8 + 30)))
                column.minWidth = 70
                column.resizingMask = .userResizingMask
                table.addTableColumn(column)
            }
        }
        if changed || coordinator.initial || structureChanged {
            let old = coordinator.cells, next = result.cells,
                origin = scroll.contentView.bounds.origin
            let reset = coordinator.initial || structureChanged
            coordinator.initial = false
            coordinator.cells = next
            if reset {
                table.reloadData()
            } else {
                let oldCount = min(old.count, previousLimit),
                    newCount = min(next.count, visibleLimit)
                if oldCount != newCount { table.noteNumberOfRowsChanged() }
                let changedRows = IndexSet(
                    (0..<newCount).filter { index in
                        fieldsChanged || !old.indices.contains(index) || old[index] != next[index]
                    })
                if !changedRows.isEmpty {
                    table.reloadData(
                        forRowIndexes: changedRows,
                        columnIndexes: IndexSet(integersIn: 0..<table.tableColumns.count))
                }
            }
            if scroll.contentView.bounds.origin != origin {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        if let selected = selection.wrappedValue, selected < table.numberOfRows {
            if table.selectedRow != selected {
                table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            }
        } else if table.selectedRow >= 0 {
            table.deselectAll(nil)
        }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
        NSTextFieldDelegate, NSPopoverDelegate {
        var parent: SQLGrid
        var cells: [[SQLCell]] = []
        var initial = true
        weak var table: NSTableView?
        var suppressSelectionChanges = false
        private var activeCell:
            (
                row: Int, column: Int, original: String,
                commit: ((Int, Int, String, @escaping (Bool) -> Void) -> Void)?
            )?
        private weak var activeField: NSTextField?
        private var popover: NSPopover?
        private var pendingClick: DispatchWorkItem?
        init(_ parent: SQLGrid) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int {
            min(cells.count, parent.visibleLimit)
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
            -> NSView? {
            guard let index = tableColumn.flatMap({ Int($0.identifier.rawValue) }),
                cells.indices.contains(row), cells[row].indices.contains(index)
            else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell =
                tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
                ?? NSTableCellView()
            cell.identifier = id
            if cell.textField == nil {
                let text = NSTextField(labelWithString: "")
                text.translatesAutoresizingMaskIntoConstraints = false
                text.lineBreakMode = .byTruncatingTail
                text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                text.delegate = self
                cell.addSubview(text)
                cell.textField = text
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let value = cells[row][index].display(binary: parent.result.fields[index].binary)
            cell.textField?.isEditable = parent.canEditCell?(row, index) == true
            cell.textField?.isSelectable = parent.canEditCell?(row, index) == true
            cell.textField?.allowsEditingTextAttributes = false
            cell.textField?.focusRingType = .none
            cell.textField?.stringValue = value
            cell.textField?.textColor =
                cells[row][index].hex == nil
                ? MokoTheme.native("SecondaryInk")
                : (parent.linkedColumn?(index) == true
                    ? MokoTheme.native("SelectionInk") : MokoTheme.native("Ink"))
            cell.toolTip =
                String(value.prefix(8192))
                + (parent.linkedColumn?(index) == true
                    ? "\nclick to view the reference; double-click to edit" : "")
            cell.setAccessibilityLabel(
                parent.result.fields[index].name + ": " + String(value.prefix(1024)))
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionChanges, let table = notification.object as? NSTableView else {
                return
            }
            let row = table.selectedRow >= 0 ? table.selectedRow : nil
            if parent.selection.wrappedValue != row {
                DispatchQueue.main.async { self.parent.selection.wrappedValue = row }
            }
        }
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            parent.sort?(tableColumn.title)
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            MokoResultRow()
        }
        func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int)
            -> Bool {
            guard let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }) else {
                return false
            }
            return parent.canEditCell?(row, column) == true
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let table else { return }
            let row = table.row(for: field), column = table.column(for: field)
            guard row >= 0, column >= 0 else { return }
            activeCell = (row, column, field.stringValue, parent.editCell)
            activeField = field
            if let editor = field.currentEditor() as? NSTextView {
                editor.selectedTextAttributes = [
                    .backgroundColor: MokoTheme.native("AccentColor").withAlphaComponent(0.3),
                    .foregroundColor: MokoTheme.native("Ink"),
                ]
            }
            parent.editingChanged?(true)
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let active = activeCell else {
                return
            }
            activeCell = nil
            activeField = nil
            if field.stringValue != active.original, let edit = active.commit {
                edit(active.row, active.column, field.stringValue) { [weak self] succeeded in
                    guard let self else { return }
                    self.parent.editingChanged?(false)
                    if !succeeded, let table = self.table, active.row < table.numberOfRows,
                        active.column < table.numberOfColumns {
                        table.reloadData(
                            forRowIndexes: IndexSet(integer: active.row),
                            columnIndexes: IndexSet(integer: active.column))
                    }
                }
            } else {
                parent.editingChanged?(false)
            }
        }
        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let activeCell,
                let activeField {
                activeField.stringValue = activeCell.original
                control.window?.makeFirstResponder(table)
                return true
            }
            return false
        }
        func copyRows(_ table: NSTableView) {
            let index = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard cells.indices.contains(index) else { return }
            let row = cells[index].enumerated().map { i, cell in
                cell.display(binary: parent.result.fields[i].binary)
            }.joined(separator: "\t")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row, forType: .string)
        }
        @objc func openRow(_ table: NSTableView) {
            pendingClick?.cancel()
            guard table.clickedRow >= 0 else { return }
            if showPopover(table.clickedRow, table.clickedColumn, editing: true) { return }
            if table.clickedColumn >= 0,
                parent.canEditCell?(table.clickedRow, table.clickedColumn) == true {
                table.editColumn(
                    table.clickedColumn, row: table.clickedRow, with: nil, select: true)
            } else {
                parent.doubleClick?(table.clickedRow)
            }
        }
        func clickedCell(_ row: Int, _ column: Int, count: Int) {
            pendingClick?.cancel()
            guard count == 1, row >= 0, column >= 0, parent.linkedColumn?(column) == true else {
                return
            }
            let work = DispatchWorkItem { [weak self] in
                _ = self?.showPopover(row, column, editing: false)
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
        @discardableResult func showPopover(_ row: Int, _ column: Int, editing: Bool) -> Bool {
            guard let table,
                let cell = table.view(atColumn: column, row: row, makeIfNecessary: true),
                let content = parent.cellPopover?(
                    row, column, editing, { [weak self] in self?.popover?.close() })
            else { return false }
            popover?.close()
            let next = NSPopover()
            next.appearance = table.effectiveAppearance
            next.behavior = .transient
            next.delegate = self
            let hosting = NSHostingController(rootView: content)
            hosting.sizingOptions = [.preferredContentSize]
            next.contentViewController = hosting
            popover = next
            parent.editingChanged?(true)
            next.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)
            return true
        }
        func popoverDidClose(_ notification: Notification) {
            guard let closed = notification.object as? NSPopover, closed === popover else { return }
            popover = nil
            parent.editingChanged?(false)
        }
        deinit {
            pendingClick?.cancel()
            popover?.close()
            parent.editingChanged?(false)
        }
    }
}
