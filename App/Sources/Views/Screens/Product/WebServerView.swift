import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct WebServerView: View {
    @ObservedObject var server: WorkspaceModel
    var body: some View { PHPWorkspace(php: server.phpServer, library: server.phpServer.projects, server: server) }
}

@available(macOS 26.0, *)
struct PHPWorkspace: View {
    @ObservedObject var php: PHPServer
    @ObservedObject var library: PHPProjectLibrary
    @ObservedObject var server: WorkspaceModel
    @State private var showLog = false
    @State private var choosingFolder = false
    @State private var showAdvanced = false
    @State private var showIntegration = false
    var connection: DatabaseConnection? {
        server.phpConnection()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Label(php.running ? "php running" : "php stopped", systemImage: "globe").font(.title2.weight(.semibold))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(library.active?.name ?? "select a project").font(.headline)
                            if !php.documentRoot.isEmpty {
                                Text((php.documentRoot as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                    .lineLimit(1).truncationMode(.middle).help(php.documentRoot)
                            }
                        }
                        Spacer()
                        if library.items.isEmpty {
                            Button("add project", systemImage: "plus") { choosingFolder = true }
                                .buttonStyle(MokoButtonStyle()).disabled(php.busy)
                        }
                    }
                    HStack {
                        Text("port").foregroundStyle(MokoTheme.secondaryInk)
                        TextField("8080", text: $php.port).textFieldStyle(.roundedBorder).frame(width: 100)
                        Text("127.0.0.1").font(.callout).foregroundStyle(MokoTheme.secondaryInk)
                        Spacer()
                    }.disabled(php.running || php.busy)
                    DisclosureGroup("advanced settings", isExpanded: $showAdvanced) {
                        HStack {
                            TextField("router script (optional)", text: $php.router).textFieldStyle(.roundedBorder)
                            Button("choose…") { chooseRouter() }.buttonStyle(MokoButtonStyle())
                        }.disabled(php.running || php.busy)
                    }
                    HStack {
                        Button(php.running ? "stop php" : "start php") {
                            if php.running { php.stop() } else { php.start(connection: connection) }
                        }.buttonStyle(MokoButtonStyle(prominent: true)).foregroundStyle(MokoTheme.onAccent).disabled(
                            php.busy)
                        if php.running, let address = php.address {
                            Button("open in browser") { NSWorkspace.shared.open(address) }.buttonStyle(
                                MokoButtonStyle())
                        }
                        if let project = library.active {
                            Menu("project actions") {
                                Button("reveal in finder") {
                                    NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
                                }
                                Button("update folder…") {
                                    php.projectPrompt = .init(project: project, kind: .updateFolder)
                                }
                                Button("remove project", role: .destructive) { php.requestRemoval(project) }
                            }.tint(MokoTheme.selectionInk).foregroundStyle(MokoTheme.ink).disabled(php.busy)
                        }
                        Button("server log") { showLog.toggle() }.buttonStyle(MokoButtonStyle())
                        if php.busy { ProgressView().controlSize(.small) }
                    }
                    if !php.error.isEmpty {
                        Text(php.error).font(.callout).foregroundStyle(MokoTheme.errorInk).textSelection(.enabled)
                    }
                }
            }
            PHPDatabaseConfiguration(server: server, projects: library, profiles: server.profiles)
            DisclosureGroup("server log", isExpanded: $showLog) {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Text(php.logTail()).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
        }
        .onChange(of: php.port) { if !php.running && !php.busy { php.saveConfiguration() } }
        .onChange(of: php.router) { if !php.running && !php.busy { php.saveConfiguration() } }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { php.requestSwitch(to: library.add(url)) }
        }
    }
    private func chooseRouter() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "php") ?? .sourceCode]
        if panel.runModal() == .OK, let url = panel.url { php.router = url.path }
    }
}
