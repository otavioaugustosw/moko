import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct PHPProjectPresentation: ViewModifier {
    @ObservedObject var php: PHPServer
    @ObservedObject var server: WorkspaceModel
    func body(content: Content) -> some View {
        content.sheet(item: $php.projectPrompt) { prompt in
            PHPProjectDialog(
                php: php, prompt: prompt,
                connectionProvider: { server.phpConnection(for: prompt.project) })
        }
    }
}

@available(macOS 26.0, *)
struct PHPProjectDialog: View {
    @ObservedObject var php: PHPServer
    let prompt: PHPProjectPrompt
    var connection: DatabaseConnection?
    var connectionProvider: (() -> DatabaseConnection?)?
    @State private var choosingFolder = false
    private var title: String {
        switch prompt.kind {
        case .switchProject: "switch php project?"
        case .missingFolder: "project folder not found"
        case .updateFolder: "update project folder"
        case .removeProject: "remove project from moko?"
        }
    }
    private var message: String {
        switch prompt.kind {
        case .switchProject:
            php.running ? "php will restart using this project." : "this project will be used when you start php."
        case .missingFolder: "choose its current folder to make this project available again."
        case .updateFolder: "choose the folder containing this project's php files."
        case .removeProject:
            php.projects.activeID == prompt.project.id && php.running
                ? "the running php server will stop. the project files stay in their folder."
                : "the project files stay in their folder."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.weight(.semibold))
            Text(prompt.project.name).font(.headline)
            Text(prompt.project.path).font(.callout).foregroundStyle(MokoTheme.secondaryInk).textSelection(.enabled)
            Text(message).foregroundStyle(MokoTheme.secondaryInk)
            HStack {
                Button("cancel", role: .cancel) { php.projectPrompt = nil }
                    .buttonStyle(MokoButtonStyle(prominent: prompt.kind == .removeProject))
                    .keyboardShortcut(prompt.kind == .removeProject ? .defaultAction : .cancelAction)
                Spacer()
                switch prompt.kind {
                case .switchProject:
                    Button("switch project") { php.confirmSwitch(to: prompt.project, connection: connectionProvider?() ?? connection) }
                        .buttonStyle(MokoButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                case .missingFolder, .updateFolder:
                    Button("choose folder…") { choosingFolder = true }.buttonStyle(MokoButtonStyle(prominent: true))
                case .removeProject:
                    Button("remove project", role: .destructive) { php.removeProject(prompt.project) }
                        .buttonStyle(MokoButtonStyle(destructive: true))
                }
            }.disabled(php.busy)
        }.padding(28).frame(width: 460).foregroundStyle(MokoTheme.ink).background(MokoTheme.canvas)
            .onExitCommand { if !php.busy { php.projectPrompt = nil } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { php.updateFolder(for: prompt.project, to: url) }
            }
    }
}
