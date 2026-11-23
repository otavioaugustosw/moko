#if DEBUG
    import SwiftUI

    private enum ObjectPreview {
        static func draft(_ kind: DatabaseObjectKind, count: Int = 0) -> NewDatabaseObjectDraft {
            var draft = NewDatabaseObjectDraft(kind: kind)
            draft.name = "calculate_total"
            draft.parameters = (0..<count).map { .init(name: "amount\($0 + 1)", type: "int") }
            draft.body = kind == .function ? "RETURN amount1" : "BEGIN\n    SELECT amount1;\nEND"
            return draft
        }
        static let definition = DatabaseObjectDefinition(
            object: .init(name: "count_items", kind: .procedure, detail: "", enabled: true),
            sql:
                "CREATE PROCEDURE count_items(IN minimum int, OUT total int) "
                + "BEGIN SELECT COUNT(*) INTO total FROM items WHERE id > minimum; END",
            body: "BEGIN SELECT COUNT(*) INTO total FROM items WHERE id > minimum; END",
            sqlMode: "STRICT_TRANS_TABLES", collation: "utf8mb4_unicode_ci",
            parameters: [
                .init(ordinal: 1, name: "minimum", mode: "IN", type: "int"),
                .init(ordinal: 2, name: "total", mode: "OUT", type: "int"),
            ])
    }

    @available(macOS 26.0, *)
    #Preview("SQL object · procedure") {
        DatabaseObjectWorkspace(library: .preview(definition: ObjectPreview.definition))
            .padding(24).frame(width: 820, height: 660).background(MokoTheme.canvas)
    }
    @available(macOS 26.0, *)
    #Preview("SQL object · dark") {
        DatabaseObjectWorkspace(
            library: .preview(definition: ObjectPreview.definition, results: [PreviewFixtures.result])
        )
        .padding(24).frame(width: 820, height: 660).background(MokoTheme.canvas).preferredColorScheme(.dark)
    }
    @available(macOS 26.0, *)
    #Preview("new procedure") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition), tables: [],
            draft: .init(kind: .procedure), close: {})
    }
    @available(macOS 26.0, *)
    #Preview("new trigger") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition),
            tables: [.init(name: "items", kind: "BASE TABLE", engine: "InnoDB", estimatedRows: "2")],
            draft: .init(kind: .trigger), close: {})
    }
    @available(macOS 26.0, *)
    #Preview("new procedure · parameters") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition), tables: [],
            draft: ObjectPreview.draft(.procedure, count: 4), close: {})
    }
    @available(macOS 26.0, *)
    #Preview("new function · dark") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition), tables: [],
            draft: ObjectPreview.draft(.function, count: 3), close: {}
        ).preferredColorScheme(.dark)
    }
    @available(macOS 26.0, *)
    #Preview("new event") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition), tables: [],
            draft: .init(kind: .event), close: {})
    }
    @available(macOS 26.0, *)
    #Preview("new view") {
        NewDatabaseObjectView(
            library: .preview(definition: ObjectPreview.definition), tables: [],
            draft: .init(kind: .view), close: {})
    }
    @available(macOS 26.0, *)
    #Preview("delete · safe default") {
        DestructiveReview(
            title: "delete procedure?", message: "this removes example.count_items.",
            actionTitle: "delete", cancel: {}, confirm: {})
    }
#endif
