import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct PHPOverview: View {
    @ObservedObject var php: PHPServer
    @ObservedObject var server: WorkspaceModel
    var configure: () -> Void
    private var state: LightState { php.busy ? .yellow : (php.running ? .green : .red) }
    private var status: String {
        if php.busy { return php.running ? "going to sleep" : "warming up" }
        return php.running ? "server running" : "server stopped"
    }
    var body: some View {
        ServerOverview(title: "php web server", state: state, status: status) {
            HStack(spacing: 8) {
                Button(php.running ? "stop php" : "start php", systemImage: php.running ? "stop.fill" : "play.fill") {
                    if php.running {
                        php.stop()
                    } else {
                        let connection = server.phpConnection()
                        php.start(connection: connection)
                    }
                }.buttonStyle(MokoButtonStyle(prominent: true)).foregroundStyle(MokoTheme.onAccent)
                    .disabled(php.busy || php.documentRoot.isEmpty)
                Menu {
                    Button("configure php", action: configure)
                    if php.running, let address = php.address {
                        Button("open website") { NSWorkspace.shared.open(address) }
                    }
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("more actions")
                }
                .menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize().tint(MokoTheme.ink)
                .accessibilityLabel("php options")
            }
        } details: {
            DetailRow(name: "address", value: "127.0.0.1:\(php.port)")
            DetailRow(name: "version", value: RuntimePaths.version(of: "php"))
            DetailRow(
                name: "project",
                value: php.documentRoot.isEmpty
                    ? "not selected" : URL(fileURLWithPath: php.documentRoot).lastPathComponent)
            DetailRow(name: "database configuration", value: php.databaseEndpoint ?? "not passed to php")
            Button("configure php", action: configure).buttonStyle(MokoButtonStyle())
            if !php.error.isEmpty {
                Text(php.error).font(.caption).foregroundStyle(MokoTheme.errorInk).textSelection(.enabled)
            }
        }
    }
}
