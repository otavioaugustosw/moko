#if DEBUG
    import SwiftUI

    // Retain each model across interactive Canvas updates, independently of other scenarios.
    @available(macOS 26.0, *)
    struct ScreenPreview: View {
        @StateObject private var model: WorkspaceModel
        let width: CGFloat
        let height: CGFloat
        init(
            page: String = "overview", running: Bool = true, tab: String = "data",
            settings: String = "connection", operation: String? = nil, width: CGFloat = 1100, height: CGFloat = 720
        ) {
            let server = PreviewFixtures.server(page: page, running: running)
            server.databaseBrowser.tab = tab
            server.settingsSection = settings
            server.serviceOperation = operation
            server.working = operation != nil
            _model = StateObject(wrappedValue: server)
            self.width = width
            self.height = height
        }
        var body: some View {
            Dashboard(model: model).frame(width: width, height: height)
                .defaultAppStorage(PreviewFixtures.preferences)
        }
    }
    #Preview("janela · servidor ligado") { ScreenPreview() }
    #Preview("janela · servidor desligado") { ScreenPreview(running: false, width: 940, height: 670) }
    #Preview("janela · aquecendo motores") { ScreenPreview(running: false, operation: "start") }
    #Preview("janela · indo dormir") { ScreenPreview(operation: "stop") }
    #Preview("window · connections") { ScreenPreview(page: "connections") }
    #Preview("janela · atividade") { ScreenPreview(page: "activity") }
    #Preview("window · connection settings") { ScreenPreview(page: "settings") }
    #Preview("window · password") { ScreenPreview(page: "settings", settings: "account") }
    #Preview("change password") {
        Dashboard(model: PreviewFixtures.server(page: "settings"), editingPassword: true).account
            .padding().frame(width: 650).preferredColorScheme(.light)
    }
    #Preview("window · application") { ScreenPreview(page: "settings", settings: "application") }
    #Preview("janela · databases") { ScreenPreview(page: "databases", width: 1280, height: 800) }
    #Preview("databases · estrutura") { ScreenPreview(page: "databases", tab: "structure", width: 1280, height: 800) }
    #Preview("databases · sql") { ScreenPreview(page: "databases", tab: "sql", width: 1280, height: 800) }
    #Preview("ONBOARDING") {
        OnboardingView(server: PreviewFixtures.server(), completed: {})
    }
#endif
