import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class MokoResultRow: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        guard let table = superview as? NSTableView else { return super.drawBackground(in: dirtyRect) }
        let row = table.row(for: self)
        MokoTheme.native(row.isMultiple(of: 2) ? "GridRow" : "GridAlternateRow").setFill()
        NSBezierPath(rect: bounds).fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        MokoTheme.native("AccentColor").withAlphaComponent(0.22).setFill()
        NSBezierPath(rect: bounds).fill()
    }
}
