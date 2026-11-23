import Foundation

enum DatabaseImportPolicyChecks {
    static func run() throws -> Int {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moko.import." + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("input.sql")
        let cases: [(DatabaseEngine, String, Bool)] = [
            (.mariadb, "USE `target`; CREATE TABLE items(id integer);", true),
            (.mariadb, "USE `other`; INSERT INTO items VALUES(1);", false),
            (.mariadb, "/*!50000 USE `other` */;", false),
            (.mariadb, "/*M!100000 DROP DATABASE target */;", false),
            (.mariadb, "CREATE OR REPLACE DATABASE target;", false),
            (.mariadb, "ALTER SCHEMA target CHARACTER SET utf8mb4;", false),
            (.mariadb, "-- USE other;\nSELECT 'USE other;', DATABASE();", true),
            (.mariadb, "CREATE PROCEDURE test() SELECT DATABASE();", true),
            (.mariadb, "USE `tar``get`;", false),
            (.postgresql, "CREATE SCHEMA work; CREATE TABLE work.items(id integer);", true),
            (.postgresql, "DROP DATABASE target;", false),
            (.postgresql, "\\connect other\nSELECT 1;", false),
            (.postgresql, "\\! echo surprise\n", false),
            (.postgresql, "\\include other.sql\n", false),
            (.postgresql, "\\copy items FROM '/tmp/file'\n", false),
            (.postgresql, "\\restrict token\nSELECT 1;\n\\unrestrict token\n", true),
            (.postgresql, "CREATE FUNCTION work.test() RETURNS text AS $$ SELECT 'USE other'; $$ LANGUAGE sql;", true),
            (.postgresql, "DO $body_12$ BEGIN RAISE NOTICE 'hello'; END $body_12$;", true),
            (.postgresql, "SELECT E'quote\\\' \\connect other'; SELECT 1;", true),
            (.postgresql, "COPY work.items FROM stdin;\n1\tUSE other;\n2\t\\N\n\\.\nSELECT 1;", true),
            (.postgresql, "COPY work.items FROM stdin;\n1\ttext\n", false),
            (.postgresql, "/* outer /* inner */ comment */ SELECT 1;", true),
            (.postgresql, "SELECT 'unfinished", false),
            (.postgresql, "DO $tag$ unfinished", false),
            (.postgresql, String(repeating: " ", count: 65533) + "/*跨界🦝*/ SELECT 1;", true),
            (.mariadb, String(repeating: " ", count: 65535) + "USE `other`;", false),
        ]
        for (index, fixture) in cases.enumerated() {
            try Data(fixture.1.utf8).write(to: file)
            var accepted = true
            do { try DatabaseImportPolicy.validate(file, engine: fixture.0, database: "target") } catch { accepted = false }
            guard accepted == fixture.2 else {
                throw DatabaseError.message("import routing regression in case \(index + 1)")
            }
        }
        print("Import: \(cases.count) routing, client command, literal, COPY and streaming checks passed.")
        return cases.count
    }
}
