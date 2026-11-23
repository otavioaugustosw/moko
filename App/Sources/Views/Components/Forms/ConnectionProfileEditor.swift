import SwiftUI

@available(macOS 26.0, *)
struct ConnectionProfileEditor: View {
    @ObservedObject var server: WorkspaceModel
    @State var profile: ConnectionProfile
    @State private var password = ""
    @State private var savePassword = true
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool {
        !profile.name.isEmpty && !profile.host.isEmpty && !profile.user.isEmpty
            && Int(profile.port).map { (1024...65535).contains($0) || !profile.managed && (1...65535).contains($0) }
                == true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile.managed ? "local server settings" : "connection profile").font(.title2.weight(.semibold))
            LabeledContent("name") { TextField("name", text: $profile.name) }
            Picker("engine", selection: $profile.engine) {
                ForEach(DatabaseEngine.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(profile.managed)
            LabeledContent("host") { TextField("host", text: $profile.host) }.disabled(profile.managed)
            LabeledContent("port") { TextField("port", text: $profile.port) }
            LabeledContent("user") { TextField("user", text: $profile.user) }.disabled(profile.managed)
            LabeledContent("default database") { TextField("optional", text: $profile.database) }
            if !profile.managed {
                LabeledContent("password") { SecureField("leave blank to keep saved password", text: $password) }
                Toggle("save password in keychain", isOn: $savePassword)
                Picker("tls", selection: $profile.tlsMode) {
                    Text("prefer encryption").tag("prefer")
                    Text("require encryption").tag("require")
                    Text("verify server identity").tag("verify-full")
                }
                if profile.tlsMode == "verify-full" {
                    LabeledContent("root certificate") { TextField("pem file path", text: $profile.rootCertificate) }
                }
            } else {
                Text("stop this service before changing its port")
                    .font(.caption).foregroundStyle(MokoTheme.secondaryInk)
            }
            if !error.isEmpty { Text(error).foregroundStyle(MokoTheme.errorInk) }
            HStack {
                Button("cancel") { dismiss() }.buttonStyle(MokoButtonStyle())
                Spacer()
                Button("save connection") { save() }.buttonStyle(MokoButtonStyle(prominent: true)).disabled(!valid)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 520)
            .foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas).tint(MokoTheme.selectionInk)
            .onChange(of: profile.engine) { _, engine in
                if !profile.managed {
                    profile.port = engine.defaultPort
                    profile.database = engine.isPostgreSQL ? "postgres" : ""
                }
            }
    }
    private func save() {
        if profile.managed {
            let active =
                profile.engine.isPostgreSQL
                ? server.postgresql.running || server.postgresql.busy
                : server.managedDatabase.running || server.managedDatabase.busy
            guard !active else {
                error = "stop this service before changing its settings"
                return
            }
        }
        if !profile.managed, savePassword, !password.isEmpty,
            !Credentials.save(password, account: profile.credentialAccount) {
            error = "could not save the password in keychain"
            return
        }
        server.profiles.save(profile)
        server.selectProfile(profile.id)
        if !password.isEmpty { server.password = password }
        dismiss()
    }
}

@available(macOS 26.0, *)
struct ConnectionProfileSettings: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var profiles: ConnectionProfiles
    @State private var editing: ConnectionProfile?
    @State private var standing = ExistingMySQLService.Standing.absent
    @State private var authorizing = false
    @State private var authorizationNotice = ""
    private var serviceAuthorization: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                standing == .ready
                    ? "authorized · no password needed"
                    : (standing == .outdated
                        ? "authorization outdated"
                        : "skip the password for start, stop and restart · any app in your account can then control it")
            ).font(.caption).foregroundStyle(MokoTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack {
                if standing != .ready {
                    Button(standing == .outdated ? "authorize again" : "authorize once") {
                        changeAuthorization { ExistingMySQLService.authorize(port: server.port, completed: $0) }
                    }.accessibilityIdentifier("mysql-authorize")
                }
                if standing != .absent {
                    Button("remove authorization") { changeAuthorization(ExistingMySQLService.revoke) }
                        .accessibilityIdentifier("mysql-revoke")
                }
                if authorizing { ProgressView().controlSize(.small) }
            }.buttonStyle(MokoButtonStyle()).disabled(authorizing || server.working)
            if !authorizationNotice.isEmpty { Text(authorizationNotice).font(.caption) }
        }.onAppear { standing = ExistingMySQLService.standing(port: server.port) }
            .onChange(of: server.port) { standing = ExistingMySQLService.standing(port: server.port) }
    }
    private func changeAuthorization(_ action: (@escaping (CommandResult) -> Void) -> Void) {
        authorizing = true
        authorizationNotice = ""
        action { result in
            authorizing = false
            standing = ExistingMySQLService.standing(port: server.port)
            authorizationNotice = result.code == 0 ? "" : result.output.lowercased()
        }
    }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("connection", selection: Binding(get: { profiles.selectedID }, set: server.selectProfile)) {
                        ForEach(profiles.items) { Text($0.name + " · " + $0.engine.rawValue).tag($0.id) }
                    }
                    Button("add", systemImage: "plus") {
                        let id = UUID()
                        editing = .init(
                            id: id, name: "new connection", engine: .postgresql, managed: false,
                            host: "127.0.0.1", port: "5432", user: "", database: "postgres",
                            tlsMode: "prefer", rootCertificate: "", credentialAccount: "moko.profile." + id.uuidString)
                    }
                }
                DetailRow(name: "engine", value: server.engine.rawValue)
                DetailRow(name: "address", value: server.host + ":" + server.port)
                DetailRow(name: "user", value: server.username)
                DetailRow(
                    name: "default database",
                    value: profiles.selected.database.isEmpty ? "none" : profiles.selected.database)
                if !profiles.selected.managed && !server.controlsExistingMySQL {
                    Text("connection only").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                }
                if server.controlsExistingMySQL { serviceAuthorization }
                HStack {
                    Button("edit") { editing = profiles.selected }
                    Button("test connection") { server.testConnection() }
                    Button("copy details", action: server.copyConnection)
                    if !profiles.selected.managed {
                        Button("remove profile", role: .destructive) {
                            profiles.remove(profiles.selectedID)
                            server.selectProfile(profiles.selectedID)
                        }
                    }
                }.buttonStyle(MokoButtonStyle()).disabled(server.working)
            }
        }.sheet(item: $editing) { ConnectionProfileEditor(server: server, profile: $0) }
    }
}
