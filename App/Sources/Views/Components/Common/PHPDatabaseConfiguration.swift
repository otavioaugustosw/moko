import AppKit
import SwiftUI

struct PHPDatabaseConfiguration: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var projects: PHPProjectLibrary
    @ObservedObject var profiles: ConnectionProfiles
    @State private var revealedPassword: String?
    @State private var notice = ""
    private var project: PHPProject? { projects.active }
    private var profile: ConnectionProfile? { profiles.items.first { $0.id == project?.connectionProfileID } }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text("project database").font(.headline)
                Picker(
                    "connection",
                    selection: Binding(get: { project?.connectionProfileID }, set: { save(profileID: $0) })
                ) {
                    Text("none").tag(nil as UUID?)
                    ForEach(profiles.items) { Text($0.name + " · " + $0.engine.rawValue).tag(Optional($0.id)) }
                }.disabled(project == nil || server.phpServer.running || server.phpServer.busy)
                if let project, let profile {
                    LabeledContent("database") {
                        TextField(
                            "database name",
                            text: Binding(
                                get: { project.database ?? profile.database },
                                set: { value in
                                    projects.associate(project, profileID: profile.id, database: value)
                                })
                        ).textFieldStyle(.roundedBorder)
                    }.disabled(server.phpServer.running || server.phpServer.busy)
                    HStack {
                        Button("copy pdo example") { copy(PHPDatabaseExample.pdo(profile.engine)) }
                        Button("copy .env") {
                            copy(
                                PHPDatabaseExample.environment(
                                    profile.connection(password: ""), database: project.database ?? profile.database,
                                    password: revealedPassword))
                        }
                        Button(revealedPassword == nil ? "include password" : "hide password") {
                            if revealedPassword != nil {
                                revealedPassword = nil
                            } else {
                                revealedPassword =
                                    profile.id == profiles.selectedID
                                    ? server.password
                                    : Credentials.read(profile.credentialAccount)
                                if revealedPassword == nil { notice = "no password is available in keychain" }
                            }
                        }
                    }.buttonStyle(MokoButtonStyle())
                    if revealedPassword != nil {
                        Text("copies include the password").font(.caption).foregroundStyle(MokoTheme.errorInk)
                    }
                }
                TransientNotice($notice)
            }
        }.onChange(of: project?.connectionProfileID) { revealedPassword = nil }
            .onChange(of: projects.activeID) { revealedPassword = nil }
    }
    private func save(profileID: UUID?) {
        guard let project else { return }
        projects.associate(project, profileID: profileID, database: "")
        revealedPassword = nil
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "copied"
    }
}
