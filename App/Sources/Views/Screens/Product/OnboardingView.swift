import SwiftUI

@available(macOS 26.0, *)
struct OnboardingView: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject private var components = RuntimeComponents.shared
    var completed: () -> Void
    var welcomeSettings = WelcomeAnimationSettings()
    var welcomeReplayToken = 0
    @State private var step = 0
    @State private var advancing = true
    @State private var setup = OnboardingConfiguration()
    @State private var preparing = false
    @State private var prepared = false
    @State private var preparationError = ""
    @Environment(\.mokoReduceMotion) private var reduceMotion
    init(
        server: WorkspaceModel, initialStep: Int = 0, welcomeSettings: WelcomeAnimationSettings = .init(),
        welcomeReplayToken: Int = 0, completed: @escaping () -> Void
    ) {
        self.server = server
        self.completed = completed
        self.welcomeSettings = welcomeSettings
        self.welcomeReplayToken = welcomeReplayToken
        _step = State(initialValue: min(6, max(0, initialStep)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("moko").font(.system(size: 40, weight: .semibold, design: .serif)).tracking(-1.5)
            ZStack {
                page.id(step).transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: advancing ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: advancing ? .leading : .trailing).combined(with: .opacity)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            footer
        }.padding(.horizontal, 40).padding(.top, 52).padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(MokoTheme.onAccent)
            .background(
                LinearGradient(
                    colors: [MokoTheme.accent, MokoTheme.onboardingEnd], startPoint: .top, endPoint: .bottom)
            )
            .tint(MokoTheme.onAccent)
            .onAppear { setup = OnboardingConfiguration(server: server) }
    }
    @ViewBuilder private var page: some View {
        switch step {
        case 0: OnboardingWelcome(settings: welcomeSettings, replayToken: welcomeReplayToken)
        case 1: OnboardingFeatures()
        case 2: OnboardingSetup(configuration: $setup)
        case 3:
            VStack(spacing: 20) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 48))
                Text("set up php now?").font(.system(size: 28, weight: .semibold))
            }
        case 4: OnboardingPHPSetup(configuration: $setup)
        case 5: OnboardingForm(title: "ai agents · optional", maximumWidth: 700) { AgentAccessPanel(compact: true) }
        default: summary
        }
    }
    private var footer: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button("back") {
                    if step <= 5 { prepared = false }
                    navigate(to: step == 5 && !setup.configurePHP ? 3 : step - 1)
                }.buttonStyle(MokoButtonStyle()).disabled(server.working || preparing)
            }
            HStack(spacing: 4) {
                ForEach(0..<7) { index in
                    Circle().fill(MokoTheme.onAccent.opacity(step == index ? 1 : 0.25)).frame(width: 6, height: 6)
                }
            }.accessibilityLabel("step \(step + 1) of 7")
            Spacer()
            if server.working || preparing { ProgressView().controlSize(.small) }
            if !preparationError.isEmpty { Text(preparationError).font(.caption).lineLimit(3).frame(maxWidth: 300) }
            if step >= 2, !server.notice.isEmpty {
                Text(server.notice.asLabel).font(.caption).lineLimit(2).frame(maxWidth: 280)
            }
            if step == 3 {
                Button("later") {
                    setup.configurePHP = false
                    prepareWorkspace()
                }.buttonStyle(MokoButtonStyle())
                    .disabled(server.working || preparing)
            }
            Button(step == 3 ? "set up php" : (step == 6 ? "open panel" : "continue")) {
                if step == 3 { setup.configurePHP = true }
                if step == 4 {
                    prepareWorkspace()
                } else if step < 6 {
                    navigate(to: step + 1)
                } else if prepared || PreviewRuntime.isActive {
                    openWorkspace()
                }
            }.buttonStyle(MokoButtonStyle(prominent: true, inverted: true))
                .disabled(
                    server.working || preparing
                        || (step == 2 && (!setup.validSQL || setup.backend == "bundled" && components.installed == nil))
                        || (step == 4 && !setup.validPHP))
        }.controlSize(.large)
    }
    private func navigate(to destination: Int) {
        advancing = destination > step
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { step = destination }
    }
    private var summary: some View {
        OnboardingForm(title: "your workspace") {
            VStack(alignment: .leading, spacing: 16) {
                DetailRow(
                    name: "sql",
                    value: setup.backend == "later"
                        ? "set up later"
                        : setup.backend == "external"
                            ? setup.engine.rawValue + " · existing server"
                            : setup.backend == "bundled"
                                ? (RuntimeComponents.included ? "mariadb · included" : "mariadb · optional")
                                : "postgresql · included")
                if setup.backend != "later" {
                    DetailRow(
                        name: "sql status",
                        value: server.connected
                            ? "connected"
                            : (setup.backend == "external"
                                ? "configured"
                                : (setup.backend == "postgresql"
                                    ? server.postgresql.running : server.managedDatabase.running)
                                    ? "running" : "ready to start"))
                }
                DetailRow(
                    name: "php",
                    value: setup.configurePHP
                        ? URL(fileURLWithPath: setup.documentRoot).lastPathComponent : "set up later")
                if setup.configurePHP {
                    DetailRow(name: "php status", value: server.phpServer.running ? "running" : "ready to start")
                }
                DetailRow(name: "ai agents", value: agentSummary)
            }
        }
    }
    private var agentSummary: String {
        AgentAccess.enabled() ? AgentAccess.mode().title : "off"
    }
    private func prepareWorkspace() {
        guard !preparing else { return }
        if PreviewRuntime.isActive {
            prepared = true
            navigate(to: 5)
            return
        }
        if setup.configurePHP && server.phpServer.running
            && URL(fileURLWithPath: setup.documentRoot).standardizedFileURL
                != URL(fileURLWithPath: server.phpServer.documentRoot).standardizedFileURL {
            preparationError = "stop php before changing its project folder"
            return
        }
        preparing = true
        preparationError = ""
        if setup.backend == "external" {
            let id =
                setup.profileID.flatMap { existing in
                    server.profiles.items.first { $0.id == existing && !$0.managed }?.id
                } ?? UUID()
            let previous = server.profiles.items.first { $0.id == id }
            let profile = ConnectionProfile(
                id: id, name: previous?.name ?? "existing server", engine: setup.engine, managed: false,
                host: setup.host, port: setup.port, user: setup.user,
                database: setup.engine.isPostgreSQL ? "postgres" : "",
                tlsMode: "prefer", rootCertificate: "",
                credentialAccount: previous?.credentialAccount ?? "moko.profile." + id.uuidString)
            server.profiles.save(profile)
            server.selectProfile(id)
            server.password = setup.password
            server.remember = setup.remember
            server.rememberCredentials()
            server.refresh()
        } else if setup.backend != "later" {
            server.selectBackend(setup.backend)
        }
        if setup.configurePHP {
            server.phpServer.registerInitialProject(URL(fileURLWithPath: setup.documentRoot), port: setup.phpPort)
        }
        if ["bundled", "postgresql"].contains(setup.backend) && setup.startDatabase {
            server.controlService(server.engine, command: "start") { success in
                if success {
                    preparePHP()
                } else {
                    preparing = false
                    preparationError = server.notice
                }
            }
        } else {
            preparePHP()
        }
    }
    private func preparePHP() {
        if setup.configurePHP && setup.startPHP {
            let connection = server.phpConnection()
            server.phpServer.start(connection: connection)
            Task { @MainActor in
                while server.phpServer.busy {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard server.phpServer.running else {
                    preparing = false
                    preparationError = server.phpServer.error
                    return
                }
                preparationFinished()
            }
        } else {
            preparationFinished()
        }
    }
    private func preparationFinished() {
        preparing = false
        prepared = true
        navigate(to: 5)
    }
    private func openWorkspace() {
        server.page = "overview"
        completed()
    }
}
