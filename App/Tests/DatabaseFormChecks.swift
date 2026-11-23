import Combine
import Foundation

// Pure regression checks: no connection or Keychain access, no SQL execution.
// Validar.sh compiles this with Core.swift, Databases.swift and the bridge objects.
@main struct CheckDatabaseForms {
    static func main() {
        _ = SQLEditorChecks.run()
        var checks = 0
        func require(_ condition: Bool, _ name: String) {
            guard condition else {
                print("databases: failed: \(name)")
                exit(1)
            }
            checks += 1
        }
        func rejects(_ draft: ColumnEditorDraft) -> Bool {
            do {
                _ = try draft.builtDefinition()
                return false
            } catch { return true }
        }
        do {
            _ = try DatabaseImportPolicyChecks.run()
            validateTemporal(require: require)
            let model = DatabaseModel()
            model.columns = [
                .init(
                    name: "nome", type: "varchar(20)", nullable: false, key: "", defaultValue: nil, extra: "",
                    collation: "", comment: ""),
                .init(
                    name: "id", type: "int", nullable: false, key: "PRI", defaultValue: nil, extra: "auto_increment",
                    collation: "", comment: ""),
            ]
            let ready = model.draft(row: nil)
            require(
                ready.values["nome"]?.mode == .value && ready.values["id"]?.mode == .omitted,
                "the form opens fillable fields and preserves the automatic identity")
            model.columns = [
                .init(
                    name: "label", type: "varchar(80)", nullable: false, key: "", defaultValue: "'it''s'",
                    extra: "", collation: "", comment: ""),
                .init(
                    name: "created", type: "datetime", nullable: false, key: "", defaultValue: "current_timestamp()",
                    extra: "", collation: "", comment: ""),
                .init(
                    name: "notes", type: "text", nullable: true, key: "", defaultValue: "NULL",
                    extra: "", collation: "", comment: ""),
            ]
            model.ddl =
                "CREATE TABLE defaults (`label` varchar(80) NOT NULL DEFAULT 'it''s',"
                + " `created` datetime NOT NULL DEFAULT current_timestamp(), `notes` text DEFAULT NULL);"
            let normalized = model.draft(row: nil)
            require(normalized.values["label"]?.text == "it's", "mariadb literal default is shown without sql quotes")
            require(normalized.values["created"]?.mode == .omitted, "timestamp default is evaluated by the server")
            require(normalized.values["notes"]?.mode == .null, "sql null is not inserted as text")
            try validateNewTable(require: require)
            try validateColumnForms(require: require, rejects: rejects)
            let defaults = UserDefaults.standard
            let savedInterval = defaults.object(forKey: "moko.databaseRefreshInterval")
            defer {
                if let savedInterval {
                    defaults.set(savedInterval, forKey: "moko.databaseRefreshInterval")
                } else {
                    defaults.removeObject(forKey: "moko.databaseRefreshInterval")
                }
            }
            let browser = DatabaseModel()
            browser.refreshInterval = 0
            let first = SQLResult(
                fields: [.init(name: "id", type: 3, binary: false), .init(name: "value", type: 253, binary: false)],
                rows: [[Data("1".utf8).hexString, Data("first".utf8).hexString]], affected: 0, truncated: false,
                warnings: 0)
            browser.consumeData(first)
            var events = 0
            let observation = browser.objectWillChange.sink { events += 1 }
            for _ in 0..<3 { browser.consumeData(first) }
            require(events == 0 && browser.data == first, "polls without changes do not redraw the grid")
            let changed = SQLResult(
                fields: first.fields, rows: [[Data("1".utf8).hexString, Data("updated".utf8).hexString]], affected: 0,
                truncated: false, warnings: 0)
            browser.consumeData(changed)
            require(
                events == 1 && browser.data?.text(0, 1) == "updated", "a real change publishes one data update")
            withExtendedLifetime(observation) {}

            // Configure the refresh policy without starting a request or running a timer.
            browser.connection = .init(host: "fixture.invalid", port: "3306", user: "fixture", password: "")
            browser.database = "fixture"
            browser.table = "table"
            browser.columns = [
                .init(
                    name: "id", type: "int", nullable: false, key: "PRI", defaultValue: nil, extra: "", collation: "",
                    comment: ""),
            ]
            browser.setWorkspaceVisible(true)
            require(!browser.automaticRefreshAllowed, "refresh stays manual when turned off")
            browser.refreshInterval = 5
            require(browser.automaticRefreshAllowed, "the five-second refresh enables visible data")
            browser.setEditorVisible(true)
            require(!browser.automaticRefreshAllowed, "editing suspends refresh without replacing the draft")
            browser.setEditorVisible(false)
            browser.setWindowVisible(false)
            require(!browser.automaticRefreshAllowed, "a hidden window suspends refresh")
            browser.setWindowVisible(true)
            browser.tab = "sql"
            require(!browser.automaticRefreshAllowed, "the sql editor receives no data polling")
            browser.tab = "data"
            browser.setWorkspaceVisible(false)
            require(!browser.automaticRefreshAllowed, "another section suspends refresh")
            browser.setWorkspaceVisible(true)
            browser.refreshInterval = 10
            require(browser.automaticRefreshAllowed, "the ten-second refresh resumes when returning to data")
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            require(browser.nextRefreshAt != nil, "timer is installed after the view update")
            var insideViewUpdate = true, synchronousPublications = 0
            let clockObservation = browser.objectWillChange.sink {
                if insideViewUpdate { synchronousPublications += 1 }
            }
            browser.setEditorVisible(true)
            require(
                !browser.automaticRefreshAllowed && synchronousPublications == 0,
                "AppKit editing callbacks pause immediately without publishing inside updateNSView")
            insideViewUpdate = false
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            require(browser.nextRefreshAt == nil, "paused clock is published on the next run-loop turn")
            browser.setEditorVisible(false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            require(browser.nextRefreshAt != nil, "clock resumes without an update-loop publication")
            withExtendedLifetime(clockObservation) {}
            browser.refreshInterval = 0
            browser.setWorkspaceVisible(false)
            browser.connection = nil
            try validateMaintenance(browser, require: require)
            print("databases: \(checks) pure form and refresh checks passed")
        } catch {
            print("databases: form checks failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    static func validateMaintenance(_ browser: DatabaseModel, require: (Bool, String) -> Void) throws {
        browser.database = "shop"
        browser.table = "it`ems"
        require(
            browser.renameTablePlan(to: "new`name").sql == "RENAME TABLE `shop`.`it``ems` TO `shop`.`new``name`;",
            "mariadb/mysql rename quotes both identifiers in the selected database")
        require(
            browser.emptyTablePlan.sql == "TRUNCATE TABLE `shop`.`it``ems`;" && browser.emptyTablePlan.destructive,
            "empty table is a destructive, reviewed plan")
        require(
            DatabaseEngine.postgresql.protectedDatabases.contains("template1")
                && DatabaseEngine.mysql.protectedDatabases.contains("performance_schema")
                && !DatabaseEngine.postgresql.protectedDatabases.contains("shop"),
            "system databases are protected per engine")
        browser.connection = .init(host: "fixture.invalid", port: "5432", user: "f", password: "", engine: .postgresql)
        browser.schema = "app"
        browser.table = "items"
        require(
            browser.renameTablePlan(to: "Stock").sql == "ALTER TABLE \"app\".\"items\" RENAME TO \"Stock\";",
            "postgresql rename keeps the schema and quotes the new name")
        browser.connection = nil
        var constraint = PostgreSQLConstraintDraft()
        constraint.name = "items_name"
        constraint.columns = ["name", "sku"]
        constraint.uniqueIndex = true
        require(
            try constraint.mysqlPlan(database: "shop", table: "items").sql
                == "CREATE UNIQUE INDEX `items_name` ON `shop`.`items` (`name`, `sku`);",
            "mariadb/mysql index form builds a quoted unique index")
        constraint.kind = .primaryKey
        constraint.name = ""
        require(
            try constraint.mysqlPlan(database: "shop", table: "items").sql
                == "ALTER TABLE `shop`.`items` ADD PRIMARY KEY (`name`, `sku`);",
            "mariadb/mysql primary key needs no name")
        constraint.kind = .foreignKey
        constraint.name = "items_owner"
        constraint.columns = ["owner"]
        constraint.referenceTable = "people"
        constraint.referenceColumns = ["id"]
        constraint.onDelete = "CASCADE"
        require(
            try constraint.mysqlPlan(database: "shop", table: "items").sql
                == "ALTER TABLE `shop`.`items` ADD CONSTRAINT `items_owner` FOREIGN KEY (`owner`) REFERENCES "
                + "`shop`.`people` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION;",
            "mariadb/mysql foreign key references the same database")
        constraint.onDelete = "SET DEFAULT"
        require(
            (try? constraint.mysqlPlan(database: "shop", table: "items")) == nil,
            "mariadb/mysql foreign key rejects set default")
        constraint.kind = .unique
        constraint.name = ""
        require(
            (try? constraint.mysqlPlan(database: "shop", table: "items")) == nil,
            "mariadb/mysql unique constraint requires a name")
    }
    private static func validateTemporal(require: (Bool, String) -> Void) {
        let temporal = SQLTemporalKind.datetime
        let originalTime = "2026-10-09 19:30:10.123456"
        let parsed = temporal.parse(originalTime)!
        require(
            temporal.string(parsed, preserving: originalTime) == originalTime,
            "date and time keep their time zone and microseconds")
        for timestamp in ["2026-10-12 09:30:10.123+00", "2026-10-12 09:30:10-03:00"] {
            require(
                temporal.parse(timestamp).map { temporal.string($0, preserving: timestamp) } == timestamp,
                "postgresql timestamp retains its precision and time zone offset")
        }
        let time = "09:30:10.123456+05:30"
        require(
            SQLTemporalKind.time.parse(time).map { SQLTemporalKind.time.string($0, preserving: time) } == time,
            "postgresql time retains its time zone offset")
        require(temporal.parse("2026-10-12 09:30:10+25:00") == nil, "invalid time zone offset is not normalized")
        require(
            SQLTemporalKind.date.parse("2026-02-30") == nil && SQLTemporalKind.date.parse("0000-00-00") == nil,
            "unrepresentable dates are not normalized by the calendar")
        require(
            SQLTemporalKind.time.parse("-25:00:00.123456") == nil && SQLTemporalKind.time.parse("838:59:59") == nil,
            "SQL durations are preserved as text instead of a 24-hour clock")
        require(
            SQLTemporalKind.time.string(
                SQLTemporalKind.time.parse("19:30:10.123456")!, preserving: "19:30:10.123456") == "19:30:10.123456",
            "the clock preserves seconds and precision")
    }
    private static func validateNewTable(require: (Bool, String) -> Void) throws {
        var draft = NewTableDraft(name: "order`items")
        let statement = try draft.plan(database: "fixture").sql
        require(
            statement.contains("`fixture`.`order``items`") && statement.contains("PRIMARY KEY (`id`)"),
            "new table quotes identifiers and creates an indexed identity")
        draft.columns.append(.init(name: "title", type: "varchar", size: "80", nullable: true))
        let nullableSQL = try draft.plan(database: "fixture").sql
        require(nullableSQL.contains("`title` varchar(80) NULL"), "nullable and size modifiers generate SQL")
        func rejects(_ candidate: NewTableDraft) -> Bool {
            do {
                _ = try candidate.plan(database: "fixture")
                return false
            } catch { return true }
        }
        draft.columns.append(.init(name: "TITLE"))
        require(rejects(draft), "duplicate column names rejected")
        draft.columns.removeLast()
        draft.columns[1].size = "80); DROP DATABASE fixture;"
        require(rejects(draft), "size input cannot inject SQL")
        draft.columns[1].size = "80"
        draft.columns[1].autoIncrement = true
        require(rejects(draft), "invalid auto increment rejected")
        require(rejects(NewTableDraft(name: "", columns: [])), "empty name rejected")
    }

    private static func validateColumnForms(require: (Bool, String) -> Void, rejects: (ColumnEditorDraft) -> Bool)
        throws {
        var risk = ColumnEditorDraft(original: "title", name: "title", definition: "varchar(80) NOT NULL")
        require(risk.changeRisks.isEmpty, "unchanged columns do not ask for a risk review")
        risk.comment = "a harmless comment"
        require(risk.changeRisks.isEmpty, "comment changes stay low code without confirmation")
        risk.parameters = "120"
        require(risk.changeRisks.isEmpty, "growing a varchar does not require a risk review")
        risk.parameters = "20"
        require(!risk.changeRisks.isEmpty, "shrinking a column requires a contextual review")
        var nullRisk = ColumnEditorDraft(original: "value", name: "value", definition: "int NULL")
        nullRisk.nullable = false
        require(!nullRisk.changeRisks.isEmpty, "disallowing existing nulls requires review")
        var enumRisk = ColumnEditorDraft(original: "state", name: "state", definition: "enum('new','done') NOT NULL")
        enumRisk.choicesText = "new"
        require(!enumRisk.changeRisks.isEmpty, "removing enum choices requires review")
        enumRisk.choicesText = "new\ndone\narchived"
        require(enumRisk.changeRisks.isEmpty, "adding enum choices stays low code")
        let source =
            "enum('a,b','x)q','it''s','semi;colon') NOT NULL DEFAULT 'it''s' COMMENT 'before ''quote'', (comment)'"
        var choice = ColumnEditorDraft(original: "choice", name: "choice", definition: source)
        require(
            choice.choicesText == "a,b\nx)q\nit's\nsemi;colon" && choice.defaultText == "it's"
                && choice.comment == "before 'quote', (comment)",
            "enum, default and comment are decoded as content")
        choice.choicesText = "hello,world\nnew)choice\nit's\n"
        let rebuiltChoice = ColumnEditorDraft(
            original: "choice", name: "choice", definition: try choice.builtDefinition())
        require(
            rebuiltChoice.choicesText == choice.choicesText && rebuiltChoice.defaultText == "it's",
            "edited enum values preserve punctuation and the empty value")
        let invisibleSource =
            "varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT '' /*!80023 INVISIBLE */ COMMENT 'keep'"
        var invisible = ColumnEditorDraft(original: "hidden", name: "hidden", definition: invisibleSource)
        require(
            invisible.invisible && invisible.defaultMode == .value && invisible.defaultText == "",
            "the invisible version comment does not leak into the default")
        invisible.invisible = false
        invisible.comment = "changed 'comment'"
        let visibleDefinition = try invisible.builtDefinition()
        let visibleForm = ColumnEditorDraft(original: "hidden", name: "hidden", definition: visibleDefinition)
        require(
            !visibleForm.invisible && visibleForm.defaultText == "" && visibleForm.comment == invisible.comment
                && !visibleDefinition.contains("*/") && !visibleDefinition.contains("/*!"),
            "turning off invisible and changing the comment leaves no stray version comment")
        invisible.invisible = true
        let hiddenDefinition = try invisible.builtDefinition()
        let hiddenForm = ColumnEditorDraft(original: "hidden", name: "hidden", definition: hiddenDefinition)
        require(
            hiddenForm.invisible && hiddenForm.comment == invisible.comment && !hiddenDefinition.contains("*/")
                && !hiddenDefinition.contains("/*!"),
            "turning invisible back on preserves the comment and leaves no stray delimiter")
        invisible.defaultMode = .null
        let nullDefinition = try invisible.builtDefinition()
        let nullForm = ColumnEditorDraft(original: "hidden", name: "hidden", definition: nullDefinition)
        require(
            nullForm.invisible && nullForm.defaultMode == .null && !nullDefinition.contains("*/")
                && !nullDefinition.contains("/*!"),
            "changing the default of an invisible column leaves no stray comment terminator")
        var numeric = ColumnEditorDraft(
            original: "number", name: "number", definition: "int NOT NULL DEFAULT '0' COMMENT 'tail'")
        numeric.unsigned = true
        numeric.zerofill = true
        let numericDefinition = try numeric.builtDefinition()
        let modifierEnd = numericDefinition.range(of: "ZEROFILL")?.upperBound
        let nullStart = numericDefinition.range(of: "NOT NULL")?.lowerBound
        let unsignedEnd = numericDefinition.range(of: "UNSIGNED")?.upperBound
        let zerofillStart = numericDefinition.range(of: "ZEROFILL")?.lowerBound
        require(
            modifierEnd != nil && nullStart != nil && modifierEnd! <= nullStart! && unsignedEnd != nil
                && zerofillStart != nil && unsignedEnd! <= zerofillStart!,
            "numeric modifiers are placed next to the type, before null and default")
        let numericForm = ColumnEditorDraft(original: "number", name: "number", definition: numericDefinition)
        require(
            numericForm.unsigned && numericForm.zerofill && !numericForm.nullable && numericForm.defaultText == "0"
                && numericForm.comment == "tail", "modifiers novos preservam os demais atributos")
        var generated = ColumnEditorDraft(
            original: "derived", name: "derived",
            definition: "int GENERATED ALWAYS AS ((`base` + 3)) STORED INVISIBLE")
        generated.comment = "result 'quoted'\\path"
        let rebuiltGenerated = ColumnEditorDraft(
            original: "derived", name: "derived", definition: try generated.builtDefinition())
        require(
            rebuiltGenerated.generated && rebuiltGenerated.invisible
                && rebuiltGenerated.comment == generated.comment,
            "generated attributes and the comment content survive the form")
        generated.defaultMode = .value
        generated.defaultText = "5"
        require(rejects(generated), "coluna gerada rejeita default manual")
        var text = ColumnEditorDraft(original: "text", name: "text", definition: "varchar(40) DEFAULT NULL")
        text.unsigned = true
        require(rejects(text), "unsigned on text is rejected before execution")
        text.unsigned = false
        text.nullable = false
        require(rejects(text), "not null with default null is rejected before execution")
        text.nullable = true
        text.parameters = "40); DROP TABLE exemplo"
        require(rejects(text), "the length does not accept a second statement")

    }
}
