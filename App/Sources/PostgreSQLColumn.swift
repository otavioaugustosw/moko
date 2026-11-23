import Foundation

struct PostgreSQLColumnDraft: Identifiable {
    let id = UUID()
    var original: String?
    var name = ""
    var type = "varchar"
    var size = "255"
    var nullable = true
    var identity = "none"
    var defaultSQL = ""
    var comment = ""
    var generated = false
    var primary = false
    var originalType = ""
    var originalDeclaration = ""
    var originalIdentity = "none"
    var originalDefault = ""
    init(column: DatabaseColumn? = nil) {
        guard let column else { return }
        original = column.name
        name = column.name
        type = column.type
        size = ""
        if let range = type.range(of: #"\([0-9]+(?:,[0-9]+)?\)"#, options: .regularExpression) {
            size = String(type[range].dropFirst().dropLast())
            type.removeSubrange(range)
        }
        type = type.replacingOccurrences(of: "character varying", with: "varchar")
            .replacingOccurrences(of: "character", with: "char")
            .replacingOccurrences(of: "timestamp without time zone", with: "timestamp")
            .replacingOccurrences(of: "timestamp with time zone", with: "timestamptz")
            .replacingOccurrences(of: "time without time zone", with: "time")
            .replacingOccurrences(of: "time with time zone", with: "timetz")
        nullable = column.nullable
        comment = column.comment
        generated = column.generated
        primary = column.key == "PRI"
        identity =
            column.extra.contains("IDENTITY ALWAYS")
            ? "always"
            : (column.extra.contains("IDENTITY DEFAULT") ? "by default" : "none")
        defaultSQL = column.defaultValue ?? ""
        originalDefault = defaultSQL
        originalType = declaration
        originalDeclaration = column.type
        originalIdentity = identity
    }
    var declaration: String {
        guard !size.isEmpty else { return type }
        let suffix = type.hasSuffix("[]") ? "[]" : ""
        let base = suffix.isEmpty ? type : String(type.dropLast(2))
        return base + "(" + size + ")" + suffix
    }
    var hasSize: Bool {
        ["varchar", "char", "numeric", "bit", "varbit", "time", "timetz", "timestamp", "timestamptz"].contains(type)
    }
    func validatedType() throws -> String {
        // Preserve types described by the server, including quoted domains, enums and arrays.
        if original != nil && originalType == declaration { return originalDeclaration }
        guard
            declaration.range(
                of: #"^[a-zA-Z_][a-zA-Z0-9_ .]*(\([0-9]+(,[0-9]+)?\))?(\[\])?$"#,
                options: .regularExpression) != nil
        else {
            throw DatabaseError.message("choose a type and a valid numeric size or precision")
        }
        return declaration
    }
    func plan(location: DatabaseLocation, table: String) throws -> SQLPlan {
        guard !name.isEmpty, name.utf8.count <= 63, !name.contains("\0") else {
            throw DatabaseError.message("enter a column name up to 63 bytes")
        }
        let type = try validatedType(), target = PostgreSQLSQL.qualified(location.schema, table)
        let identifier = PostgreSQLSQL.identifier(name)
        var statements = [String]()
        let identitySQL =
            identity == "none" ? "" : " GENERATED " + (identity == "always" ? "ALWAYS" : "BY DEFAULT") + " AS IDENTITY"
        if let original {
            if original != name {
                statements.append(
                    "ALTER TABLE \(target) RENAME COLUMN \(PostgreSQLSQL.identifier(original)) TO \(identifier)")
            }
            if !generated && originalType != declaration {
                statements.append(
                    "ALTER TABLE \(target) ALTER COLUMN \(identifier) TYPE \(type) USING \(identifier)::\(type)")
            }
            if !generated {
                statements.append(
                    "ALTER TABLE \(target) ALTER COLUMN \(identifier) " + (nullable && !primary ? "DROP" : "SET")
                        + " NOT NULL")
                if originalIdentity != identity {
                    if originalIdentity != "none" && identity != "none" {
                        statements.append(
                            "ALTER TABLE \(target) ALTER COLUMN \(identifier) SET GENERATED "
                                + (identity == "always" ? "ALWAYS" : "BY DEFAULT"))
                    } else if originalIdentity != "none" {
                        statements.append("ALTER TABLE \(target) ALTER COLUMN \(identifier) DROP IDENTITY")
                    } else if identity != "none" {
                        if !originalDefault.isEmpty {
                            statements.append("ALTER TABLE \(target) ALTER COLUMN \(identifier) DROP DEFAULT")
                        }
                        statements.append("ALTER TABLE \(target) ALTER COLUMN \(identifier) ADD" + identitySQL)
                    }
                }
                if identity == "none" && originalDefault != defaultSQL {
                    statements.append(
                        "ALTER TABLE \(target) ALTER COLUMN \(identifier) "
                            + (defaultSQL.isEmpty ? "DROP DEFAULT" : "SET DEFAULT " + defaultSQL))
                }
            }
        } else {
            statements.append(
                "ALTER TABLE \(target) ADD COLUMN \(identifier) \(type)" + identitySQL
                    + (nullable ? "" : " NOT NULL")
                    + (defaultSQL.isEmpty || identity != "none" ? "" : " DEFAULT " + defaultSQL))
        }
        statements.append("COMMENT ON COLUMN \(target).\(identifier) IS \(PostgreSQLSQL.literal(comment))")
        return .init(
            title: "save column", sql: statements[0], database: location.database,
            summary: name, statements: statements)
    }
}
