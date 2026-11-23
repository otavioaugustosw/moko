import SwiftUI

struct ConnectionProfilePicker: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var profiles: ConnectionProfiles
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("connection").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
            Picker("connection", selection: Binding(get: { profiles.selectedID }, set: server.selectProfile)) {
                ForEach(DatabaseEngine.allCases) { engine in
                    Section(engine.rawValue) {
                        ForEach(profiles.items.filter { $0.engine == engine }) { Text($0.name).tag($0.id) }
                    }
                }
            }.labelsHidden().pickerStyle(.menu).disabled(server.working)
            Text(profiles.selected.engine.rawValue + " · " + server.host + ":" + server.port)
                .font(.caption2).foregroundStyle(MokoTheme.secondaryInk).lineLimit(2)
        }
    }
}
