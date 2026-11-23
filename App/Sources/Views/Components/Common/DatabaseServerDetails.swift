import SwiftUI

@available(macOS 26.0, *)
struct DatabaseServerDetails: View {
    @ObservedObject var model: WorkspaceModel
    let showsConnections: Bool
    let transition: AnyTransition

    var body: some View {
        Group {
            DetailRow(
                name: "address", value: "\(model.host):\(model.actualPort == "—" ? model.port : model.actualPort)")
            DetailRow(
                name: "account", value: model.account == "waiting for connection" ? model.username : model.account)
            DetailRow(name: "engine", value: model.engine.rawValue)
            DetailRow(name: "version", value: model.version)
            DetailRow(name: "server hostname", value: model.serverName == "—" ? model.host : model.serverName)
            if showsConnections {
                Button(action: model.showSessions) {
                    DetailRow(name: "connections", value: model.connections)
                }.buttonStyle(.plain).help("view connected sessions").transition(transition)
            }
        }
    }
}
