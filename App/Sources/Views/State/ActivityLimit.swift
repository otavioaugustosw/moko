import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ActivityLimit: Int, CaseIterable {
    case all = 0, ten = 10, thirty = 30
    var title: String { self == .all ? "all events" : "last \(rawValue) events" }
}
