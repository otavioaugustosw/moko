import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LocalDatabaseOverview: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var postgres: ManagedPostgreSQL
    @ObservedObject var mariadb: ManagedDatabase
    @ObservedObject private var components = RuntimeComponents.shared
    let engine: DatabaseEngine
    private var running: Bool { engine.isPostgreSQL ? postgres.running : mariadb.running }
    private var busy: Bool { engine.isPostgreSQL ? postgres.busy : mariadb.busy }
    private var error: String { engine.isPostgreSQL ? postgres.error : mariadb.error }
    private var port: String { engine.isPostgreSQL ? postgres.port : mariadb.port }
    private var operation: String { engine.isPostgreSQL ? postgres.operation : mariadb.operation }
    private var directory: URL { engine.isPostgreSQL ? postgres.dataDirectory : mariadb.dataDirectory }
    var body: some View {
        ServerOverview(
            title: engine.rawValue + " server", state: busy ? .yellow : (running ? .green : .red),
            status: busy
                ? (operation == "stop" ? "going to sleep" : "warming up")
                : (running ? "server running" : "server stopped")
        ) {
            HStack(spacing: 8) {
                Button(running ? "stop" : "start", systemImage: running ? "stop.fill" : "play.fill") {
                    server.controlService(engine, command: running ? "stop" : "start")
                }.buttonStyle(MokoButtonStyle(prominent: !running))
                if running {
                    Button("restart", systemImage: "arrow.clockwise") {
                        server.controlService(engine, command: "restart")
                    }
                    .buttonStyle(MokoButtonStyle()).disabled(!engine.isPostgreSQL && components.installed == nil)
                }
                Menu {
                    Button("use in database editor") {
                        server.selectProfile(ConnectionProfile.local(engine).id)
                        server.page = "databases"
                    }
                    Button("open data folder") { NSWorkspace.shared.open(directory) }
                    Button("components") {
                        server.page = "settings"
                        server.settingsSection = "components"
                    }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("more actions")
                }
                .menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize().tint(MokoTheme.ink)
            }.disabled(busy || (!engine.isPostgreSQL && components.busy))
        } details: {
            DetailRow(name: "address", value: "127.0.0.1:" + port)
            DetailRow(
                name: "version",
                value: engine.isPostgreSQL
                    ? RuntimePaths.version(of: "libpq") : components.installed?.version ?? "unavailable")
            DetailRow(name: "user", value: "moko")
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(MokoTheme.errorInk) }
        }
    }
}
