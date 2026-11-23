import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class DatabaseResultTable: NSTableView {
    var copySelection: (() -> Void)?
    var clickedCell: ((Int, Int, Int) -> Void)?
    @objc func copy(_ sender: Any?) { copySelection?() }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        super.mouseDown(with: event)
        clickedCell?(row, column, event.clickCount)
    }
}
