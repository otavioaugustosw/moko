import Foundation

enum DatabaseChecks {
    static func inspect(_ connection: DatabaseConnection) -> Bool {
        let result = connection.execute("SHOW DATABASES")
        guard result.succeeded else {
            print("databases: connection not confirmed (\(result.code))")
            return false
        }
        print("databases: \(result.results.first?.rows.count ?? 0) accessible databases")
        return true
    }
    // Only this unique, newly created fixture is mutated. Existing schemas are never edited.
    static func validate(_ connection: DatabaseConnection) -> Bool {
        let database = "moko_validation_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let quotedDatabase = DatabaseSQL.identifier(database)
        var created = false
        var cleaned = false
        var checks = 0
        func require(_ condition: Bool, _ name: String) throws {
            guard condition else { throw DatabaseError.message(name) }
            checks += 1
        }
        func run(_ sql: String, multiple: Bool = false, oneRow: Bool = false, formSession: Bool = false) throws
            -> SQLResponse {
            return try checkedResponse(
                connection.execute(
                    sql, database: created ? database : "", multiple: multiple, oneRow: oneRow, formSession: formSession
                ))
        }
        func cleanup() {
            guard created && !cleaned else { return }
            cleaned = connection.execute("DROP DATABASE \(quotedDatabase)").succeeded
            print(cleaned ? "test database removed" : "could not remove the test database: \(database)")
        }
        defer { cleanup() }
        do {
            _ = try run("CREATE DATABASE \(quotedDatabase) CHARACTER SET utf8mb4")
            created = true
            let target = DatabaseSQL.qualified(database, "linhas`teste")
            let columns = try createRecordFixture(
                target: target, request: { try run($0, multiple: $1, oneRow: $2, formSession: $3) })
            let text = "Olá 😀\nlinha\t'\\\u{0}; DROP DATABASE outro;"
            let values = initialRecordValues(columns: columns, text: text)
            let insert = try DatabaseSQL.rowPlan(
                database: database, table: "linhas`teste", columns: columns, draft: .init(original: nil, values: values)
            )
            _ = try run(insert.sql, oneRow: true)
            let selection =
                "SELECT " + columns.map { DatabaseSQL.identifier($0.name) }.joined(separator: ",") + " FROM \(target)"
            var result = try run(selection).results[0]
            try require(result.text(0, 2) == text && result.cells[0][3].hex == "00ff270a", "texto e bytes preservados")
            try require(result.text(0, 1) == "18446744073709551614", "bigint unsigned without loss of precision")
            try require(
                result.text(0, 4) == "1.25" && result.text(0, 5) == "2" && result.text(0, 6) == "x",
                "defaults, generated and invisible columns")
            let original = result.cells[0]
            var draft = RowDraft(
                original: original,
                values: Dictionary(
                    uniqueKeysWithValues: zip(columns, original).map {
                        ($0.name, CellDraft(text: $1.display(binary: $0.binary), mode: $1.hex == nil ? .null : .value))
                    }))
            draft.values["texto"] = .init(text: "", mode: .value)
            let edit = try DatabaseSQL.rowPlan(
                database: database, table: "linhas`teste", columns: columns, draft: draft)
            _ = try run(edit.sql, oneRow: true)
            try require(try run(selection).results[0].text(0, 2) == "", "editar chave composta e string vazia")
            let conflict = connection.execute(edit.sql, database: database, oneRow: true)
            try require(conflict.code == 409 && conflict.rolledBack, "a conflict does not overwrite the newer version")
            result = try run(selection).results[0]
            draft = RowDraft(
                original: result.cells[0],
                values: Dictionary(
                    uniqueKeysWithValues: zip(columns, result.cells[0]).map {
                        ($0.name, CellDraft(text: $1.display(binary: $0.binary), mode: $1.hex == nil ? .null : .value))
                    }))
            draft.values["texto"] = .init(text: "", mode: .null)
            _ = try run(
                try DatabaseSQL.rowPlan(database: database, table: "linhas`teste", columns: columns, draft: draft).sql,
                oneRow: true)
            try require(try run(selection).results[0].rows[0][2] == nil, "null distinto de vazio")
            _ = try run("UPDATE \(target) SET numero=2.50")
            result = try run(selection).results[0]
            draft = RowDraft(
                original: result.cells[0],
                values: Dictionary(
                    uniqueKeysWithValues: zip(columns, result.cells[0]).map {
                        ($0.name, CellDraft(text: $1.display(binary: $0.binary), mode: $1.hex == nil ? .null : .value))
                    }))
            draft.values["numero"] = .init(text: "", mode: .omitted)
            _ = try run(
                try DatabaseSQL.rowPlan(database: database, table: "linhas`teste", columns: columns, draft: draft).sql,
                oneRow: true)
            try require(try run(selection).results[0].text(0, 4) == "1.25", "restore the default while editing")
            result = try run(selection).results[0]
            draft = RowDraft(
                original: result.cells[0],
                values: Dictionary(
                    uniqueKeysWithValues: zip(columns, result.cells[0]).map {
                        ($0.name, CellDraft(text: $1.display(binary: $0.binary), mode: $1.hex == nil ? .null : .value))
                    }))
            draft.values["numero"] = .init(text: "não é um número", mode: .value)
            let invalid = connection.execute(
                try DatabaseSQL.rowPlan(database: database, table: "linhas`teste", columns: columns, draft: draft).sql,
                database: database, oneRow: true)
            try require(
                !invalid.succeeded && invalid.rolledBack && (try run(selection).results[0].text(0, 4) == "1.25"),
                "invalid values are not converted with loss")
            let ddl = try run("SHOW CREATE TABLE \(target)").results[0].text(0, 1)!
            let definition = DatabaseSQL.columnDefinition("texto", ddl: ddl)
            try require(
                definition?.contains("COMMENT") == true && definition?.contains("COLLATE") == true,
                "atributos da coluna preservados")
            _ = try run("ALTER TABLE \(target) CHANGE COLUMN `texto` `texto_novo` \(definition!)")
            try require(
                try run("SHOW COLUMNS FROM \(target) LIKE 'texto_novo'").results[0].rows.count == 1,
                "renomear coluna e preservar atributos")
            _ = try run(
                "ALTER TABLE \(target) ADD COLUMN `adicional` int DEFAULT 5; CREATE INDEX `idx_adicional` ON \(target)(`adicional`)",
                multiple: true)
            try require(
                try run("SHOW INDEX FROM \(target) WHERE Key_name = 'idx_adicional'").results[0].rows.count == 1,
                "add a column and an index")
            _ = try run("CREATE VIEW v_linhas AS SELECT grupo, id, texto_novo FROM \(target)")
            let view = try run(
                DatabaseSQL.tableMetadata(database: database, table: "v_linhas"), multiple: true, formSession: true)
            try require(
                view.results.count == 4 && view.results[0].rows.count == 3 && view.results[2].rows.isEmpty,
                "view structure can be read")
            let noChange = try run("UPDATE \(target) SET numero=numero")
            try require(noChange.results[0].affected == 0, "real change count in the console")
            let row = try run(selection.replacingOccurrences(of: "`texto`", with: "`texto_novo`")).results[0].cells[0]
            let renamed = columns.map { column in
                column.name == "texto"
                    ? DatabaseColumn(
                        name: "texto_novo", type: column.type, nullable: column.nullable, key: column.key,
                        defaultValue: column.defaultValue, extra: column.extra, collation: column.collation,
                        comment: column.comment) : column
            }
            _ = try run(
                try DatabaseSQL.deletePlan(database: database, table: "linhas`teste", columns: renamed, row: row).sql,
                oneRow: true)
            try require(try run("SELECT * FROM \(target)").results[0].rows.isEmpty, "deletion of one row")
            try validateConsole(
                connection, database: database, target: target, columns: columns, original: original, text: text,
                request: { try run($0, multiple: $1, oneRow: $2, formSession: $3) }, require: require)
            // Exercise the low-code editor against MySQL normalization and real defaults,
            // including clauses whose SQL contains commas, parentheses and apostrophes.
            try validateAttributes(
                connection, database: database, request: { try run($0, multiple: $1, oneRow: $2, formSession: $3) },
                require: require)
            try validateReferences(
                database: database, request: { try run($0, multiple: $1, oneRow: $2, formSession: $3) },
                require: require)
            cleanup()
            try require(cleaned, "cleanup of the isolated database")
            print("databases: \(checks) checks passed")
            return true
        } catch {
            print("databases: validation failed: \(error.localizedDescription)")
            return false
        }
    }
    private static func initialRecordValues(columns: [DatabaseColumn], text: String) -> [String: CellDraft] {
        var values = Dictionary(
            uniqueKeysWithValues: columns.map { ($0.name, CellDraft(text: "", mode: .omitted)) })
        values["grupo"] = .init(text: "1", mode: .value)
        values["id"] = .init(text: "18446744073709551614", mode: .value)
        values["texto"] = .init(text: text, mode: .value)
        values["bytes"] = .init(text: "0x00ff270a", mode: .value)
        return values
    }
    private static func checkedResponse(_ response: SQLResponse) throws -> SQLResponse {
        guard response.succeeded else { throw DatabaseError.message("\(response.error) (\(response.code))") }
        return response
    }
    typealias Request = (String, Bool, Bool, Bool) throws -> SQLResponse
    typealias Requirement = (Bool, String) throws -> Void
    private static func validateAttributes(
        _ connection: DatabaseConnection, database: String, request: Request, require: Requirement
    ) throws {
        func run(_ sql: String, multiple: Bool = false, oneRow: Bool = false, formSession: Bool = false) throws
            -> SQLResponse { try request(sql, multiple, oneRow, formSession) }
        let attributes = DatabaseSQL.qualified(database, "atributos")
        _ = try run(
            """
            CREATE TABLE \(attributes) (
              `id` bigint unsigned NOT NULL AUTO_INCREMENT,
              `base` int NOT NULL DEFAULT 2,
              `choice` enum('a,b','x)q','it''s','semi;colon') NOT NULL DEFAULT 'it''s' COMMENT 'antes ''aspas'', (comentário)',
              `updated` timestamp(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
              `expression_value` varchar(30) DEFAULT (concat('one,','two)')),
              `generated` int GENERATED ALWAYS AS ((`base` + 3)) STORED,
              `hidden` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT '' INVISIBLE,
              `label` varchar(40) NOT NULL DEFAULT 'stay',
              `risk` varchar(20) DEFAULT NULL,
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB;
            """)
        func attributeDDL() throws -> String { try run("SHOW CREATE TABLE \(attributes)").results[0].text(0, 1)! }
        func editor(_ name: String) throws -> ColumnEditorDraft {
            guard let definition = DatabaseSQL.columnDefinition(name, ddl: try attributeDDL()) else {
                throw DatabaseError.message("definition not found: \(name)")
            }
            return .init(original: name, name: name, definition: definition)
        }
        func columnMetadata(_ name: String) throws -> SQLResult {
            try run("SHOW FULL COLUMNS FROM \(attributes) WHERE Field = \(DatabaseSQL.literal(name))").results[0]
        }
        for name in ["choice", "updated", "expression_value", "generated", "hidden"] {
            var form = try editor(name)
            let before = try columnMetadata(name)
            form.name = name + "_new"
            _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: form).sql)
            let after = try columnMetadata(form.name)
            try require(
                after.rows.count == 1 && Array(before.rows[0].dropFirst()) == Array(after.rows[0].dropFirst()),
                "renaming \(name) preserves modifiers and expression")
        }
        var identity = try editor("id")
        identity.comment = "chave 'nova', (descrição)\\caminho"
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: identity).sql)
        let identityMetadata = try columnMetadata("id")
        try require(
            identityMetadata.text(0, 1)?.contains("unsigned") == true && identityMetadata.text(0, 4) == "PRI"
                && identityMetadata.text(0, 6)?.contains("auto_increment") == true
                && identityMetadata.text(0, 8) == identity.comment,
            "the comment preserves unsigned, key and auto_increment")
        var label = try editor("label")
        label.nullable = true
        label.invisible = true
        label.comment = "campo 'opcional', (visível no editor)"
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: label).sql)
        var labelMetadata = try columnMetadata("label")
        try require(
            labelMetadata.text(0, 3) == "YES" && labelMetadata.text(0, 5) == "stay"
                && labelMetadata.text(0, 6)?.contains("INVISIBLE") == true
                && labelMetadata.text(0, 8) == label.comment, "toggles alteram null e invisible preservando default"
        )
        _ = try run("INSERT INTO \(attributes)(base,risk) VALUES (2,'not-numeric')")
        let defaults = try run(
            "SELECT id,choice_new,expression_value_new,generated_new,hidden_new,label,updated_new IS NOT NULL FROM \(attributes)"
        ).results[0]
        try require(
            defaults.text(0, 0) == "1" && defaults.text(0, 1) == "it's" && defaults.text(0, 2) == "one,two)"
                && defaults.text(0, 3) == "5" && defaults.text(0, 4) == "" && defaults.text(0, 5) == "stay"
                && defaults.text(0, 6) == "1", "defaults, generated columns and identity work after the form")
        let beforeUpdate = try run("SELECT updated_new FROM \(attributes)").results[0].text(0, 0)
        _ = try run("DO SLEEP(0.01)")
        _ = try run("UPDATE \(attributes) SET base=3 WHERE id=1")
        let afterUpdate = try run("SELECT updated_new,generated_new FROM \(attributes)").results[0]
        try require(
            afterUpdate.text(0, 0) != beforeUpdate && afterUpdate.text(0, 1) == "6",
            "on update and the generated expression are preserved after a rename")
        label = try editor("label")
        label.defaultMode = .value
        label.defaultText = "valor 'novo'\\path"
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: label).sql)
        _ = try run("INSERT INTO \(attributes)(base) VALUES (4)")
        try require(
            try run("SELECT label FROM \(attributes) WHERE id=2").results[0].text(0, 0) == label.defaultText,
            "a default with an apostrophe and a backslash keeps its content")
        label = try editor("label")
        label.defaultMode = .value
        label.defaultText = ""
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: label).sql)
        labelMetadata = try columnMetadata("label")
        try require(labelMetadata.text(0, 5) == "", "default vazio permanece diferente de null")
        label = try editor("label")
        label.defaultMode = .null
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: label).sql)
        labelMetadata = try columnMetadata("label")
        try require(
            labelMetadata.rows[0][5] == nil && labelMetadata.text(0, 3) == "YES",
            "toggling default null keeps the column nullable")
        let originalBaseValues = try run("SELECT base FROM \(attributes) ORDER BY id").results[0].rows
        var base = try editor("base")
        base.unsigned = true
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: base).sql)
        let unsignedMetadata = try columnMetadata("base")
        try require(
            unsignedMetadata.text(0, 1)?.contains("unsigned") == true && unsignedMetadata.text(0, 3) == "NO"
                && unsignedMetadata.text(0, 5) == "2", "turning on unsigned on a column with a default produces valid SQL")
        base = try editor("base")
        base.unsigned = false
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: base).sql)
        let signedMetadata = try columnMetadata("base")
        base = try editor("base")
        base.unsigned = true
        _ = try run(try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: base).sql)
        try require(
            signedMetadata.text(0, 1)?.contains("unsigned") == false
                && (try columnMetadata("base").text(0, 1)?.contains("unsigned") == true)
                && (try run("SELECT base FROM \(attributes) ORDER BY id").results[0].rows == originalBaseValues),
            "desativar e reativar unsigned preserva os valores existentes")
        var risk = try editor("risk")
        risk.typeName = "int"
        risk.parameters = ""
        let lossy = connection.execute(
            try DatabaseSQL.columnPlan(database: database, table: "atributos", draft: risk).sql, database: database)
        let riskMetadata = try columnMetadata("risk")
        try require(
            !lossy.succeeded && riskMetadata.text(0, 1)?.hasPrefix("varchar") == true
                && (try run("SELECT risk FROM \(attributes)").results[0].text(0, 0) == "not-numeric"),
            "changing the type refuses a lossy conversion and preserves the content")
    }
    private static func validateReferences(database: String, request: Request, require: Requirement) throws {
        func run(_ sql: String, multiple: Bool = false, oneRow: Bool = false, formSession: Bool = false) throws
            -> SQLResponse { try request(sql, multiple, oneRow, formSession) }
        _ = try run(
            """
            CREATE TABLE parent_ref (grupo int NOT NULL, codigo varchar(50) NOT NULL, nome varchar(60), PRIMARY KEY(grupo,codigo));
            INSERT INTO parent_ref VALUES (7,'a''b; value','referência exata'), (8,'a''b; value','outra referência');
            CREATE TABLE child_ref (id int PRIMARY KEY, grupo int, codigo varchar(50), data date, horario time(6), momento datetime(6), FOREIGN KEY(grupo,codigo) REFERENCES parent_ref(grupo,codigo));
            INSERT INTO child_ref VALUES (1,7,'a''b; value','2026-10-09','19:30:10.123456','2026-10-09 19:30:10.654321');
            """, multiple: true)
        let relationMetadata = try run(
            DatabaseSQL.tableMetadata(database: database, table: "child_ref"), multiple: true, formSession: true)
        let fields = relationMetadata.results[0]
        let relationColumns = fields.rows.indices.map { i in
            DatabaseColumn(
                name: fields.text(i, 0)!, type: fields.text(i, 1)!, nullable: fields.text(i, 2) == "YES",
                key: fields.text(i, 3) ?? "", defaultValue: fields.text(i, 4), extra: fields.text(i, 5) ?? "",
                collation: fields.text(i, 6) ?? "", comment: fields.text(i, 7) ?? "")
        }
        let child = try run("SELECT * FROM child_ref").results[0].cells[0]
        let reference = ForeignKeyTarget.make(
            metadata: relationMetadata.results[3], columns: relationColumns, row: child, column: 2)!
        let preview = try run(reference.query).results[0]
        try require(
            preview.rows.count == 1 && preview.text(0, 2) == "referência exata",
            "the composite FK preview uses every column and escapes values")
        var nullKey = child
        nullKey[1] = .init(hex: nil)
        try require(
            ForeignKeyTarget.make(
                metadata: relationMetadata.results[3], columns: relationColumns, row: nullKey, column: 2) == nil,
            "an FK with a null component does not navigate to another row")
        var temporalDraft = RowDraft(
            original: child,
            values: Dictionary(
                uniqueKeysWithValues: zip(relationColumns, child).map {
                    ($0.name, CellDraft(text: $1.display(), mode: $1.hex == nil ? .null : .value))
                }))
        temporalDraft.values["data"] = .init(text: "2026-10-23", mode: .value)
        temporalDraft.values["horario"] = .init(text: "20:45:12.123456", mode: .value)
        _ = try run(
            try DatabaseSQL.rowPlan(
                database: database, table: "child_ref", columns: relationColumns, draft: temporalDraft
            ).sql, oneRow: true)
        let savedDates = try run("SELECT data,horario,momento FROM child_ref").results[0]
        try require(
            savedDates.text(0, 0) == "2026-10-23" && savedDates.text(0, 1) == "20:45:12.123456"
                && savedDates.text(0, 2) == "2026-10-09 19:30:10.654321",
            "temporal editing preserves precision and untouched fields")
    }
    private static func validateConsole(
        _ connection: DatabaseConnection, database: String, target: String, columns: [DatabaseColumn],
        original: [SQLCell], text: String, request: Request, require: Requirement
    ) throws {
        func run(_ sql: String, multiple: Bool = false, oneRow: Bool = false, formSession: Bool = false) throws
            -> SQLResponse { try request(sql, multiple, oneRow, formSession) }
        let mode = try run(
            "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; SELECT \(DatabaseSQL.literal(text)), NULL, '', X'00ff'",
            multiple: true
        ).results.last!
        try require(
            mode.text(0, 0) == text && mode.rows[0][1] == nil && mode.text(0, 2) == "" && mode.rows[0][3] == "00ff",
            "sql mode e transporte de valores")
        let rollback = try run("START TRANSACTION; INSERT INTO \(target)(grupo,id) VALUES (2,2)", multiple: true)
        try require(
            rollback.rolledBack && (try run("SELECT * FROM \(target)").results[0].rows.isEmpty),
            "incomplete transaction rolled back")
        let partial = connection.execute(
            "INSERT INTO \(target)(grupo,id) VALUES (3,3); SELECT * FROM tabela_inexistente", database: database,
            multiple: true)
        try require(
            !partial.succeeded && partial.results.count == 1 && partial.results[0].affected == 1,
            "a script error preserves earlier results")
        let limited = connection.execute("SELECT 1 UNION ALL SELECT 2", database: database, maxRows: 1)
        try require(
            limited.results[0].truncated && limited.results[0].rows.count == 1, "explicit result limits")
        var denied = false
        do {
            _ = try DatabaseSQL.predicate(
                columns: columns.filter { $0.key != "PRI" }, original: Array(original.dropFirst(2)))
        } catch { denied = true }
        try require(denied, "editing without a primary key is blocked")
    }
    private static func createRecordFixture(target: String, request: Request) throws -> [DatabaseColumn] {
        func run(_ sql: String, multiple: Bool = false, oneRow: Bool = false, formSession: Bool = false) throws
            -> SQLResponse { try request(sql, multiple, oneRow, formSession) }
        _ = try run(
            """
            CREATE TABLE \(target) (`grupo` int NOT NULL, `id` bigint unsigned NOT NULL,
              `texto` varchar(255) COLLATE utf8mb4_0900_ai_ci DEFAULT NULL COMMENT 'teste, (sql)',
              `bytes` varbinary(20) DEFAULT NULL, `numero` decimal(12,2) NOT NULL DEFAULT 1.25,
              `gerada` int GENERATED ALWAYS AS (`grupo` + 1) STORED,
              `oculta` varchar(10) DEFAULT 'x' INVISIBLE, PRIMARY KEY (`grupo`,`id`)) ENGINE=InnoDB;
            """)
        let metadata = try run("SHOW FULL COLUMNS FROM \(target)").results[0]
        let columns = metadata.rows.indices.map { i in
            DatabaseColumn(
                name: metadata.text(i, 0)!, type: metadata.text(i, 1)!, nullable: metadata.text(i, 3) == "YES",
                key: metadata.text(i, 4) ?? "", defaultValue: metadata.text(i, 5), extra: metadata.text(i, 6) ?? "",
                collation: metadata.text(i, 2) ?? "", comment: metadata.text(i, 8) ?? "")
        }
        return columns
    }
}
