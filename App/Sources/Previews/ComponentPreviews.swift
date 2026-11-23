#if DEBUG
    import SwiftUI

    #Preview("traffic light · states") {
        HStack {
            TrafficLight(state: .red)
            TrafficLight(state: .yellow)
            TrafficLight(state: .green)
        }.padding()
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("card and details") {
        Surface { DetailRow(name: "servidor", value: "localhost:3306") }.padding().frame(width: 400)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("material lateral") {
        WindowSidebarMaterial().frame(width: 210, height: 500)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("database navigator") {
        DatabaseNavigator(browser: PreviewFixtures.browser()).padding().frame(width: 210, height: 500)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("barra contextual") {
        let server = PreviewFixtures.server()
        return MokoContextSidebar(model: server, browser: server.databaseBrowser, filters: PanelFilters())
            .frame(width: 210, height: 600)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("sql grid · editable cells") {
        SQLGrid(
            result: PreviewFixtures.result, canEditCell: { _, _ in true },
            editCell: { _, _, _, completed in completed(true) }
        ).frame(width: 750, height: 300)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("refresh clock") {
        RefreshClock(browser: PreviewFixtures.browser()).padding()
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("nova linha") {
        RowEditor(
            browser: PreviewFixtures.browser(), columns: PreviewFixtures.columns,
            draft: PreviewFixtures.row(), submit: { _ in }
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("editar linha") {
        RowEditor(
            browser: PreviewFixtures.browser(), columns: PreviewFixtures.columns,
            draft: PreviewFixtures.row(editing: true), submit: { _ in }
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("editar coluna") {
        ColumnEditor(
            browser: PreviewFixtures.browser(),
            draft: .init(original: "nome", name: "nome", definition: "varchar(80) NOT NULL"), submit: { _ in }
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("confirm deletion") {
        DatabaseConfirmation(
            plan: .init(title: "delete table", sql: "", database: "example", destructive: true),
            browser: PreviewFixtures.browser(), close: {}
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("content field") {
        @Previewable @State var text = "editable content"
        SQLValueField(column: PreviewFixtures.columns[1], text: $text).padding().frame(width: 350)
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("calendar") {
        @Previewable @State var date = Date()
        NativeSQLDatePicker(kind: .date, value: $date).frame(width: 180, height: 180).padding()
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("time") {
        SQLTemporalEditor(name: "horario", kind: .time, value: "19:30:00", save: { _, done in done(nil) }, close: {})
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
    #Preview("data e hora") {
        SQLTemporalEditor(
            name: "atualizado", kind: .datetime, value: "2026-10-11 19:30:00",
            save: { _, done in done(nil) }, close: {}
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("foreign key reference") {
        ForeignKeyPreview(
            target: .init(
                constraint: "fk_categoria", database: "exemplo", table: "categorias",
                predicate: "id = 1", summary: "id = 1"),
            connection: .init(host: "preview", port: "3306", user: "exemplo", password: ""),
            initialResponse: .init(results: [PreviewFixtures.result], code: 0, error: "", rolledBack: false), open: {}
        )
        .preferredColorScheme(.light)
        .background(Color.white)
        .tint(MokoTheme.selectionInk)
    }
    #Preview("new database") {
        DatabaseWorkspace(server: PreviewFixtures.server(), browser: PreviewFixtures.browser()).newDatabaseForm
            .preferredColorScheme(.light)
            .background(Color.white)
            .tint(MokoTheme.selectionInk)
    }
#endif
