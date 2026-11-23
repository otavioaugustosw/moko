import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SessionScope: String, CaseIterable {
    case all, active, idle
    var title: String {
        switch self {
        case .all: "all"
        case .active: "active"
        case .idle: "idle"
        }
    }
    var icon: String {
        switch self {
        case .all: "personalhotspot"
        case .active: "bolt"
        case .idle: "moon"
        }
    }
    func includes(_ session: ServerSession) -> Bool {
        switch self {
        case .all: true
        case .active: session.command != "Sleep"
        case .idle: session.command == "Sleep"
        }
    }
}
