import SwiftUI
import UniformTypeIdentifiers

struct OnboardingConfiguration {
    var backend = "postgresql"
    var engine: DatabaseEngine = .postgresql
    var profileID: UUID?
    var startDatabase = true
    var host = "127.0.0.1", port = "3306", user = "root", password = ""
    var remember = true
    var configurePHP = false
    var startPHP = false
    var documentRoot = "", phpPort = "8080"
    var validSQL: Bool {
        backend != "external" || (!host.isEmpty && !user.isEmpty && Int(port).map { (1...65535).contains($0) } == true)
    }
    var validPHP: Bool {
        PHPProject(path: documentRoot).available && Int(phpPort).map { (1024...65535).contains($0) } == true
    }
    init() {}
    init(server: WorkspaceModel) {
        backend = server.backend
        engine = server.engine
        profileID = server.profiles.selectedID
        startDatabase = server.usesBundledDatabase && !server.running
        remember = server.remember
        if !server.usesBundledDatabase {
            host = server.host
            port = server.port
            user = server.username
            password = server.password
        }
        documentRoot = server.phpServer.documentRoot
        phpPort = server.phpServer.port
    }
}

@available(macOS 26.0, *)
struct OnboardingSetup: View {
    @Binding var configuration: OnboardingConfiguration
    @ObservedObject private var components = RuntimeComponents.shared
    var body: some View {
        OnboardingForm(title: "set up sql", maximumWidth: 820) {
            HStack(alignment: .top, spacing: 20) {
                SQLSetupSelector(selection: $configuration.backend).frame(width: 330)
                Divider()
                details.frame(maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
        }.onChange(of: configuration.backend) { _, backend in
            configuration.startDatabase = backend == "postgresql"
        }.onChange(of: configuration.engine) { _, engine in
            configuration.port = engine.defaultPort
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if configuration.backend == "postgresql" {
                Text("port 15432")
                    .font(.callout.weight(.medium)).foregroundStyle(MokoTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("start postgresql now", isOn: $configuration.startDatabase)
            } else if configuration.backend == "bundled" {
                if RuntimeComponents.included {
                    Text("port 13306")
                        .font(.callout.weight(.medium)).foregroundStyle(MokoTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MariaDBInstallation(components: components) { components.install($0) }
                }
                if components.installed != nil {
                    Toggle("start mariadb after setup", isOn: $configuration.startDatabase)
                }
            } else if configuration.backend == "later" {
                EmptyView()
            } else {
                Picker("engine", selection: $configuration.engine) {
                    ForEach(DatabaseEngine.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("onboarding-engine")
                OnboardingField(name: "host", text: $configuration.host)
                OnboardingField(name: "port", text: $configuration.port)
                OnboardingField(name: "user", text: $configuration.user)
                HStack {
                    Text("password").frame(width: 75, alignment: .leading)
                    SecureField("password", text: $configuration.password)
                        .accessibilityIdentifier("onboarding-password")
                }.textFieldStyle(.roundedBorder)
                Toggle("save password in keychain", isOn: $configuration.remember).font(.callout)
                    .accessibilityIdentifier("onboarding-save-password")
            }
        }
    }
}

@available(macOS 26.0, *)
struct OnboardingPHPSetup: View {
    @Binding var configuration: OnboardingConfiguration
    @State private var choosingFolder = false
    var body: some View {
        OnboardingForm(title: "set up php") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("project folder", text: $configuration.documentRoot).textFieldStyle(.roundedBorder)
                Button("choose folder…") { choosingFolder = true }.buttonStyle(MokoButtonStyle())
                OnboardingField(name: "port", text: $configuration.phpPort)
                Toggle("start php when opening the panel", isOn: $configuration.startPHP)
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { configuration.documentRoot = url.path }
        }
    }
}

@available(macOS 26.0, *)
struct OnboardingForm<Content: View>: View {
    let title: String
    var maximumWidth: CGFloat = 540
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .vertical) {
            form.fixedSize(horizontal: false, vertical: true)
            ScrollView { form }.scrollIndicators(.visible)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var form: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 28, weight: .semibold))
            Surface { content.frame(maxWidth: .infinity, alignment: .leading) }
                .foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
                .frame(maxWidth: maximumWidth)
        }.frame(maxWidth: .infinity)
    }
}

struct OnboardingField: View {
    let name: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(name).frame(width: 75, alignment: .leading)
            TextField(name, text: $text).accessibilityIdentifier("onboarding-" + name)
        }.textFieldStyle(.roundedBorder)
    }
}
