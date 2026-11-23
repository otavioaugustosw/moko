import AppKit
import SwiftUI
import XCTest

@testable import mokoInterfaceHost

@MainActor
final class NativeComponentTests: XCTestCase {
    func testGridKeepsSelectionAcrossSilentRefreshAndClearsInvalidSelection() throws {
        var selection: Int? = 1
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let hosting = NSHostingView(rootView: SQLGrid(result: PreviewFixtures.result, selection: binding))
        let window = host(hosting)
        defer { window.contentView = nil; window.close() }
        let table = try XCTUnwrap(descendant(NSTableView.self, in: hosting))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRow, 1)
        hosting.rootView = SQLGrid(result: PreviewFixtures.result, selection: binding)
        settle(hosting)
        XCTAssertEqual(table.selectedRow, 1)
        XCTAssertEqual(selection, 1)
        let shortened = SQLResult(
            fields: PreviewFixtures.result.fields, rows: Array(PreviewFixtures.result.rows.prefix(1)),
            affected: 0, truncated: false, warnings: 0)
        hosting.rootView = SQLGrid(result: shortened, selection: binding)
        settle(hosting)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(table.selectedRow, -1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "1")
    }

    func testSQLParameterCompletionAndHighlightUseReadableThemeColors() throws {
        for dark in [false, true] {
            var text = "SELECT amount, total FROM invoices"
            let binding = Binding<String>(get: { text }, set: { text = $0 })
            let root = SQLBodyEditor(text: binding, parameters: ["amount", "total"]).preferredColorScheme(
                dark ? .dark : .light)
            let hosting = NSHostingView(rootView: root), window = host(hosting)
            defer { window.contentView = nil; window.close() }
            let editor = try XCTUnwrap(descendant(ParameterTextView.self, in: hosting))
            let coordinator = try XCTUnwrap(editor.delegate as? SQLBodyEditor.Coordinator)
            XCTAssertEqual(editor.string, text)
            editor.string = "SELECT am"
            let options = coordinator.textView(
                editor, completions: [], forPartialWordRange: NSRange(location: 7, length: 2),
                indexOfSelectedItem: nil)
            XCTAssertEqual(options, ["amount"])
            editor.string = text
            coordinator.highlight(editor)
            let storage = try XCTUnwrap(editor.textStorage)
            let nameColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor)
            let bodyColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            editor.effectiveAppearance.performAsCurrentDrawingAppearance {
                XCTAssertEqual(nameColor.usingColorSpace(.sRGB), MokoTheme.native("SelectionInk").usingColorSpace(.sRGB))
                XCTAssertEqual(bodyColor.usingColorSpace(.sRGB), MokoTheme.native("Ink").usingColorSpace(.sRGB))
            }
        }
    }

    private func host<Content: View>(_ hosting: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        settle(hosting)
        return window
    }
    private func settle(_ hosting: NSView) {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    }
    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }
}
