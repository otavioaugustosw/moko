import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PanelFilters: ObservableObject {
    @Published var sessionQuery = ""
    @Published var sessionScope: SessionScope = .all
    @Published var sessionDatabase: String?
    @Published var activityQuery = ""
    @Published var activityLimit: ActivityLimit = .all
    @Published var oldestFirst = false

    var hasSessionFilters: Bool {
        !sessionQuery.isEmpty || sessionScope != .all || sessionDatabase != nil
    }
    var hasActivityFilters: Bool { !activityQuery.isEmpty || activityLimit != .all || oldestFirst }
    func sessions(_ source: [ServerSession]) -> [ServerSession] {
        let query = sessionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { session in
            sessionScope.includes(session)
                && (sessionDatabase == nil || sessionDatabase == session.database)
                && (query.isEmpty
                    || "\(session.id) \(session.user) \(session.host) \(session.database) \(session.command) \(session.state)"
                        .localizedStandardContains(query))
        }
    }
    func events(_ source: [Event]) -> [Event] {
        let query = activityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = source.filter { query.isEmpty || $0.text.localizedStandardContains(query) }
        if activityLimit != .all { result = Array(result.prefix(activityLimit.rawValue)) }
        if oldestFirst { result.reverse() }
        return result
    }
    func clearSessions() {
        sessionQuery = ""
        sessionScope = .all
        sessionDatabase = nil
    }
    func clearActivity() {
        activityQuery = ""
        activityLimit = .all
        oldestFirst = false
    }
}
