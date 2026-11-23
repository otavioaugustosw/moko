import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension Dashboard {

    var connectedSessions: some View {
        let sessions = filters.sessions(model.sessions)
        return Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(
                        model.sessionUpdatedAt == nil
                            ? "sessions"
                            : (filters.hasSessionFilters
                                ? "\(sessions.count) of \(model.sessions.count) \(model.sessions.count == 1 ? "session" : "sessions")"
                                : "\(sessions.count) \(sessions.count == 1 ? "session" : "sessions")")
                    ).font(.headline)
                    Spacer()
                    Button("refresh") { model.refresh(manual: true) }.buttonStyle(MokoButtonStyle())
                        .foregroundStyle(.primary).disabled(model.working)
                }
                if !model.sessionError.isEmpty {
                    Label(model.sessionError.lowercased(), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(MokoTheme.secondaryInk)
                } else if !model.connected {
                    Text(
                        model.running
                            ? "not connected"
                            : "server stopped"
                    ).foregroundStyle(MokoTheme.secondaryInk)
                } else if model.sessionUpdatedAt == nil {
                    ProgressView("loading sessions…")
                } else if model.sessions.isEmpty {
                    Text("no other connected sessions").foregroundStyle(MokoTheme.secondaryInk)
                } else if sessions.isEmpty {
                    Text("no sessions match these filters").foregroundStyle(MokoTheme.secondaryInk)
                    Button("clear filters", action: filters.clearSessions).buttonStyle(MokoButtonStyle())
                } else {
                    Table(sessions) {
                        TableColumn("user") { session in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.user).lineLimit(1)
                                Text("id \(session.id)").font(.caption2).foregroundStyle(MokoTheme.secondaryInk)
                            }.help(session.user)
                        }.width(85)
                        TableColumn("host") {
                            Text($0.host.isEmpty ? "—" : $0.host).lineLimit(1).help($0.host)
                        }.width(125)
                        TableColumn("database") {
                            Text($0.database.isEmpty ? "—" : $0.database).lineLimit(1).help(
                                $0.database)
                        }.width(90)
                        TableColumn("state") { session in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.command.lowercased()).lineLimit(1)
                                Text(
                                    session.state.isEmpty
                                        ? (session.command == "Sleep" ? "idle" : "—")
                                        : session.state.lowercased()
                                ).font(.caption2).foregroundStyle(MokoTheme.secondaryInk).lineLimit(1)
                            }.help(session.state)
                        }.width(100)
                        TableColumn("time") { Text("\($0.seconds) s").monospacedDigit() }.width(45)
                    }.frame(height: 320)
                }
                Image(systemName: "info.circle").foregroundStyle(MokoTheme.secondaryInk).help(
                    """
                    your account determines which sessions are visible. without the process privilege, only sessions \
                    from your account are shown.
                    """
                )
            }
        }
    }
}
