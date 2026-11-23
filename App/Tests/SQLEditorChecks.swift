import Foundation

enum SQLEditorChecks {
    static func run() -> Int {
        var checks = 0
        func require(_ condition: Bool, _ name: String) {
            guard condition else { print("SQL editor: " + name); exit(1) }
            checks += 1
        }
        let sql = "SELECT amount, amount_total, `amount`, 'amount', \"amount\"; -- amount\nSET amount=1; /* amount */ # amount"
        let ranges = SQLParameterSyntax.highlights(sql, parameters: ["amount"])
        require(ranges.map { (sql as NSString).substring(with: $0) } == ["amount", "`amount`", "amount"],
                "only complete SQL parameter identifiers are highlighted")
        let unicode = "SELECT '🦝', résumé"
        require(SQLParameterSyntax.highlights(unicode, parameters: ["résumé"]) == [(unicode as NSString).range(of: "résumé")],
                "highlight ranges use UTF-16 offsets after emoji")
        require(SQLParameterSyntax.highlights("'it\\'s amount' 'amount''amount'", parameters: ["amount"]).isEmpty,
                "escaped and doubled quotes do not expose parameters")
        let completions = SQLParameterSyntax.completion("SELECT AM", caret: 9, parameters: ["amount", "amount_total", "amount"])
        require(Set(completions?.suggestions ?? []) == ["amount", "amount_total"], "completion is case-insensitive and deduplicated")
        require(completions?.range == NSRange(location: 7, length: 2), "completion replaces only the prefix at the caret")
        for sql in ["SELECT 'am", "-- am", "/* am", "# am", "SELECT \"am"] {
            require(SQLParameterSyntax.completion(sql, caret: sql.utf16.count, parameters: ["amount"]) == nil,
                    "no completion in strings or comments")
        }
        require(SQLParameterSyntax.completion("SELECT amount", caret: 13, parameters: ["amount"]) == nil,
                "complete parameter names do not reopen suggestions")
        require(SQLParameterSyntax.completion("SELECT am ", caret: 10, parameters: ["amount"]) == nil,
                "whitespace ends completion")
        require(RoutineSQLType.selecting("varchar", current: "int") == "varchar(255)", "varchar has a usable initial length")
        require(RoutineSQLType.selecting("decimal", current: "int") == "decimal(12,2)", "decimal exposes precision and scale")
        require(RoutineSQLType.selecting("varchar", current: "varchar(42)") == "varchar(42)", "reselecting a type preserves its size")
        require(RoutineSQLType.resizing("20,4", current: "decimal(12,2) unsigned") == "decimal(20,4) unsigned",
                "size editing preserves numeric modifiers")
        for type in RoutineSQLType.choices {
            var draft = NewDatabaseObjectDraft(kind: .function)
            draft.name = "sample"
            draft.body = "RETURN NULL"
            draft.returns = RoutineSQLType.selecting(type, current: "")
            require((try? draft.statement(database: "example")) != nil, "dropdown type is accepted by the SQL form: " + type)
        }
        print("SQL editor: \(checks) parameter, completion and type checks passed.")
        return checks
    }
}
