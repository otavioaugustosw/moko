import Foundation

enum PostgreSQLObjectChecks {
    static func run(_ fixture: PostgreSQLCheckFixture) throws {
        let library = DatabaseObjectLibrary()
        library.configure(connection: fixture.connection, database: fixture.database)
        wait(library)
        try fixture.require(library.error.isEmpty, "object catalog failed: " + library.error)
        var function = NewDatabaseObjectDraft(kind: .function)
        function.name = "calculate"
        function.parameters = [.init(name: "amount", type: "integer")]
        function.returns = "integer"
        function.body = "BEGIN RETURN amount + 1; END"
        try create(function, library: library, fixture: fixture)
        try select("calculate", kind: .function, library: library, fixture: fixture)
        try fixture.require(library.definition?.parameters.first?.name == "amount", "parameter metadata failed")
        library.run(values: [1: "4"], nulls: [])
        wait(library)
        try fixture.require(library.results.first?.text(0, 0) == "5", "function invocation failed: " + library.error)
        try library.saveBody("BEGIN RETURN amount + 2; END") { _ in }
        wait(library)
        try fixture.require(
            fixture.query("SELECT work.calculate(4)").results.first?.text(0, 0) == "6", "function replacement failed")
        try library.saveBody("BEGIN RETURN (; END") { _ in }
        wait(library)
        try fixture.require(
            !library.error.isEmpty && fixture.query("SELECT work.calculate(4)").results.first?.text(0, 0) == "6",
            "invalid body replacement did not preserve routine")
        function.parameters = [.init(name: "amount", type: "text")]
        function.language = "sql"
        function.body = "SELECT length(amount)"
        try create(function, library: library, fixture: fixture)
        try fixture.require(library.items.filter { $0.name == "calculate" }.count == 2, "overloads were conflated")
        var procedure = NewDatabaseObjectDraft(kind: .procedure)
        procedure.name = "with_output"
        procedure.parameters = [
            .init(name: "amount", type: "integer"), .init(name: "total", type: "integer", mode: "OUT"),
        ]
        procedure.body = "BEGIN total := amount * 2; END"
        try create(procedure, library: library, fixture: fixture)
        try select(procedure.name, kind: .procedure, library: library, fixture: fixture)
        library.run(values: [1: "7"], nulls: [])
        wait(library)
        try fixture.require(library.results.first?.text(0, 0) == "14", "procedure output failed: " + library.error)
        try triggers(library, fixture: fixture)
        try views(library, fixture: fixture)
        var sequence = NewDatabaseObjectDraft(kind: .sequence)
        sequence.name = "ticket_numbers"
        sequence.sequenceStart = "10"
        sequence.sequenceIncrement = "2"
        try create(sequence, library: library, fixture: fixture)
        try select(sequence.name, kind: .sequence, library: library, fixture: fixture)
        try fixture.require(
            library.definition?.sql.contains("INCREMENT BY 2") == true, "sequence definition lost its attributes")
        try fixture.require(
            fixture.query("SELECT nextval('work.ticket_numbers')").results.first?.text(0, 0) == "10",
            "sequence start failed")
        library.deleteSelected { _ in }
        wait(library)
        try fixture.require(!library.items.contains { $0.name == sequence.name }, "sequence deletion failed")
        var schema = NewDatabaseObjectDraft(kind: .schema)
        schema.name = "extra"
        try create(schema, library: library, fixture: fixture)
        try fixture.require(
            library.items.contains { $0.kind == .schema && $0.name == "extra" }, "schema catalog failed")
        try select(schema.name, kind: .schema, library: library, fixture: fixture)
        library.deleteSelected { _ in }
        wait(library)
        try fixture.require(!library.items.contains { $0.name == schema.name }, "schema deletion failed")
    }
    private static func wait(_ library: DatabaseObjectLibrary) { PostgreSQLRuntimeChecks.wait { !library.busy } }
    private static func create(
        _ draft: NewDatabaseObjectDraft, library: DatabaseObjectLibrary, fixture: PostgreSQLCheckFixture
    ) throws {
        try library.create(draft) { _ in }
        wait(library)
        try fixture.require(
            library.error.isEmpty && library.items.contains { $0.name == draft.name && $0.kind == draft.kind },
            "object creation failed: " + draft.name + " " + library.error)
    }
    private static func select(
        _ name: String, kind: DatabaseObjectKind, library: DatabaseObjectLibrary, fixture: PostgreSQLCheckFixture
    ) throws {
        guard let object = library.items.first(where: { $0.name == name && $0.kind == kind }) else {
            throw DatabaseError.message("object missing from catalog: " + name)
        }
        library.select(object)
        wait(library)
        try fixture.require(library.definition != nil && library.error.isEmpty, "definition failed: " + library.error)
    }
    private static func triggers(_ library: DatabaseObjectLibrary, fixture: PostgreSQLCheckFixture) throws {
        var function = NewDatabaseObjectDraft(kind: .function)
        function.name = "uppercase_name"
        function.returns = "trigger"
        function.body = "BEGIN NEW.name := upper(NEW.name); RETURN NEW; END"
        try create(function, library: library, fixture: fixture)
        try fixture.require(
            library.items.contains { $0.name == function.name && $0.resultType == "trigger" },
            "trigger function metadata failed")
        var trigger = NewDatabaseObjectDraft(kind: .trigger)
        trigger.name = "capitalize"
        trigger.table = "items"
        trigger.triggerFunction = function.name
        trigger.triggerEvent = "UPDATE"
        try create(trigger, library: library, fixture: fixture)
        try fixture.require(
            fixture.query("UPDATE work.items SET name='hello'").succeeded
                && fixture.query("SELECT name FROM work.items").results.first?.text(0, 0) == "HELLO",
            "trigger invocation failed")
        try select(trigger.name, kind: .trigger, library: library, fixture: fixture)
        library.setTriggerEnabled(false)
        wait(library)
        try fixture.require(library.items.first { $0.name == trigger.name }?.enabled == false, "trigger disable failed")
        try fixture.require(
            fixture.query("UPDATE work.items SET name='hello'").succeeded
                && fixture.query("SELECT name FROM work.items").results.first?.text(0, 0) == "hello",
            "disabled trigger executed")
        library.setTriggerEnabled(true)
        wait(library)
        try fixture.require(library.items.first { $0.name == trigger.name }?.enabled == true, "trigger enable failed")
    }
    private static func views(_ library: DatabaseObjectLibrary, fixture: PostgreSQLCheckFixture) throws {
        var view = NewDatabaseObjectDraft(kind: .view)
        view.name = "item_names"
        view.body = "SELECT id,name FROM work.items"
        try create(view, library: library, fixture: fixture)
        try fixture.require(
            fixture.query("ALTER VIEW work.item_names SET (security_barrier=true)").succeeded,
            "view options fixture failed")
        try select(view.name, kind: .view, library: library, fixture: fixture)
        try library.saveBody("SELECT id,name FROM work.items WHERE active") { _ in }
        wait(library)
        try fixture.require(
            library.error.isEmpty && library.definition?.sql.contains("security_barrier=true") == true,
            "view replacement lost security options: " + library.error)
        view.kind = .materializedView
        view.name = "item_snapshot"
        view.body = "SELECT id,name FROM work.items"
        try create(view, library: library, fixture: fixture)
        try select(view.name, kind: .materializedView, library: library, fixture: fixture)
        try fixture.require(!library.editable, "materialized view allowed destructive body replacement")
        library.refreshMaterializedView()
        wait(library)
        try fixture.require(
            library.error.isEmpty
                && fixture.query("SELECT name FROM work.item_snapshot").results.first?.text(0, 0) == "hello",
            "materialized view refresh failed")
    }
}
