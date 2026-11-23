#if DEBUG
    import SwiftUI

    @available(macOS 26.0, *)
    private struct PostgreSQLWorkspacePreview: View {
        @StateObject private var server = PreviewFixtures.server(page: "databases")
        @StateObject private var browser = PreviewFixtures.browser(engine: .postgresql)
        var tab = "data"
        var body: some View {
            DatabaseWorkspace(server: server, browser: browser).frame(width: 960, height: 640)
                .onAppear { browser.tab = tab }
        }
    }

    @available(macOS 26.0, *)
    #Preview("postgresql · data · light") { PostgreSQLWorkspacePreview().preferredColorScheme(.light) }
    @available(macOS 26.0, *)
    #Preview("postgresql · data · dark") { PostgreSQLWorkspacePreview().preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("postgresql · structure") { PostgreSQLWorkspacePreview(tab: "structure") }
    @available(macOS 26.0, *)
    #Preview("postgresql · new table") { NewTableView(browser: PreviewFixtures.browser(engine: .postgresql)) }
    @available(macOS 26.0, *)
    #Preview("postgresql · index") { PostgreSQLConstraintEditor(browser: PreviewFixtures.browser(engine: .postgresql)) }
    @available(macOS 26.0, *)
    #Preview("postgresql · foreign key · dark") {
        PostgreSQLConstraintEditor(
            browser: PreviewFixtures.browser(engine: .postgresql),
            draft: .init(kind: .foreignKey)
        ).preferredColorScheme(.dark)
    }
    @available(macOS 26.0, *)
    #Preview("postgresql · numeric column") {
        PostgreSQLColumnEditor(
            browser: PreviewFixtures.browser(engine: .postgresql),
            draft: .init(
                column: .init(
                    name: "price", type: "numeric(12,2)", nullable: false,
                    key: "", defaultValue: "0", extra: "", collation: "", comment: "", engine: .postgresql)))
    }
#endif
