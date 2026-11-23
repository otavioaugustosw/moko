import Foundation

enum PostgreSQLTypeChecks {
    static func run(_ fixture: PostgreSQLCheckFixture) throws {
        try fixture.require(
            fixture.query(
                """
                CREATE TYPE work."Mood state" AS ENUM ('happy','calm');
                CREATE TABLE work.types (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                  mood work."Mood state", instant timestamp(3) with time zone,
                  labels character varying(20)[], generated integer GENERATED ALWAYS AS (1) STORED);
                INSERT INTO work.types(mood,instant,labels) VALUES('happy','2026-10-12 12:00:00+00',ARRAY['a']);
                """, multiple: true
            ).succeeded, "typed column fixture failed")
        let response = fixture.query(PostgreSQLSQL.metadata(schema: "work", table: "types"), multiple: true)
        try fixture.require(response.succeeded, "typed column metadata failed")
        let result = response.results[0], location = DatabaseLocation(database: fixture.database, schema: "work")
        for row in result.rows.indices {
            let column = DatabaseColumn(
                name: result.text(row, 0) ?? "", type: result.text(row, 1) ?? "",
                nullable: result.text(row, 2) == "YES", key: result.text(row, 3) ?? "",
                defaultValue: result.text(row, 4), extra: result.text(row, 5) ?? "",
                collation: result.text(row, 6) ?? "",
                comment: result.text(row, 7) ?? "", engine: .postgresql)
            var draft = PostgreSQLColumnDraft(column: column)
            draft.comment = "metadata preserved"
            if column.name == "id" { draft.identity = "by default" }
            let plan = try draft.plan(location: location, table: "types")
            try fixture.require(fixture.apply(plan).succeeded, "column attributes were lost: " + column.type)
        }
        try fixture.require(
            fixture.query("INSERT INTO work.types(mood) VALUES('calm')").succeeded,
            "changing identity mode reset the sequence")
        try fixture.require(
            fixture.query("SELECT max(id) FROM work.types").results.first?.text(0, 0) == "2",
            "identity sequence value was not preserved")
        try fixture.require(
            fixture.query("DROP TABLE work.types; DROP TYPE work.\"Mood state\"", multiple: true).succeeded,
            "typed column fixture cleanup failed")
    }
}
