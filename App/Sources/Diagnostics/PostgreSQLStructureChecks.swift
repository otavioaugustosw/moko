import Foundation

enum PostgreSQLStructureChecks {
    static func run(_ fixture: PostgreSQLCheckFixture) throws {
        let location = DatabaseLocation(database: fixture.database, schema: "work")
        try fixture.require(
            fixture.query("CREATE TABLE work.links (item_id bigint, label text, score integer)").succeeded,
            "constraint fixture failed")
        var draft = PostgreSQLConstraintDraft()
        draft.name = "links_label"
        draft.columns = ["label"]
        try fixture.require(
            fixture.apply(try draft.plan(location: location, table: "links")).succeeded,
            "index form failed")
        draft.kind = .unique
        draft.name = "links_unique"
        draft.columns = ["item_id", "label"]
        draft.deferrable = true
        try fixture.require(
            fixture.apply(try draft.plan(location: location, table: "links")).succeeded,
            "unique constraint form failed")
        draft.kind = .check
        draft.name = "links_score"
        draft.expression = "score >= 0"
        try fixture.require(
            fixture.apply(try draft.plan(location: location, table: "links")).succeeded,
            "check constraint form failed")
        draft.kind = .foreignKey
        draft.name = "links_item"
        draft.columns = ["item_id"]
        draft.referenceSchema = "work"
        draft.referenceTable = "items"
        draft.referenceColumns = ["id"]
        draft.onDelete = "CASCADE"
        try fixture.require(
            fixture.apply(try draft.plan(location: location, table: "links")).succeeded,
            "foreign key form failed")
        try fixture.require(fixture.query("INSERT INTO work.links VALUES(2,'ok',1)").succeeded, "valid FK failed")
        let invalid = fixture.query("INSERT INTO work.links VALUES(999,'invalid',1)")
        try fixture.require(!invalid.succeeded && invalid.sqlState == "23503", "foreign key did not enforce its target")
        try fixture.require(
            !fixture.query("INSERT INTO work.links VALUES(2,'negative',-1)").succeeded,
            "check constraint did not enforce its expression")
        let metadata = fixture.query(PostgreSQLSQL.metadata(schema: "work", table: "links"), multiple: true)
        try fixture.require(metadata.succeeded && metadata.results.count == 5, "constraint catalog failed")
        let constraints = metadata.results[4], indexes = metadata.results[2]
        try fixture.require(constraints.rows.count == 3, "constraint list is incomplete")
        try fixture.require(
            indexes.rows.indices.filter { indexes.text($0, 4) == "t" }.count == 1,
            "constraint index was not distinguished from an independent index")
        let target = ForeignKeyTarget.make(
            metadata: metadata.results[3],
            columns: [
                .init(
                    name: "item_id", type: "bigint", nullable: true, key: "", defaultValue: nil, extra: "",
                    collation: "", comment: "", engine: .postgresql),
            ], row: [.init(hex: Data("2".utf8).hexString)], column: 0, engine: .postgresql)
        try fixture.require(target?.schema == "work" && target?.table == "items", "FK preview target lost its schema")
        try fixture.require(target.map { fixture.query($0.query).succeeded } == true, "FK preview query failed")
        try fixture.require(
            fixture.query("ALTER INDEX work.links_label RENAME TO links_label_renamed").succeeded,
            "index rename failed")
        try fixture.require(
            fixture.query("ALTER TABLE work.links RENAME CONSTRAINT links_score TO positive_score").succeeded,
            "constraint rename failed")
        try fixture.require(fixture.query("DROP INDEX work.links_label_renamed").succeeded, "index deletion failed")
        try fixture.require(
            fixture.query("ALTER TABLE work.links DROP CONSTRAINT positive_score").succeeded,
            "constraint deletion failed")
        try fixture.require(fixture.query("DROP TABLE work.links").succeeded, "constraint fixture cleanup failed")
    }
}
