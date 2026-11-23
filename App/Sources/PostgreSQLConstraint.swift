import Foundation

struct PostgreSQLConstraintDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case index, primaryKey = "primary key", unique, foreignKey = "foreign key", check
        var id: String { rawValue }
    }
    let id = UUID()
    var kind: Kind = .index
    var name = ""
    var columns: [String] = []
    var uniqueIndex = false
    var method = "btree"
    var referenceSchema = "public"
    var referenceTable = ""
    var referenceColumns: [String] = []
    var onDelete = "NO ACTION"
    var onUpdate = "NO ACTION"
    var deferrable = false
    var expression = ""
    mutating func select(_ column: String, selected: Bool, reference: Bool = false) {
        if reference {
            referenceColumns.removeAll { $0 == column }
            if selected { referenceColumns.append(column) }
        } else {
            columns.removeAll { $0 == column }
            if selected { columns.append(column) }
        }
    }
    func plan(location: DatabaseLocation, table: String) throws -> SQLPlan {
        guard !name.isEmpty, name.utf8.count <= 63, !name.contains("\0") else {
            throw DatabaseError.message("enter a constraint or index name up to 63 bytes")
        }
        guard kind == .check || !columns.isEmpty else { throw DatabaseError.message("select at least one column") }
        let target = PostgreSQLSQL.qualified(location.schema, table)
        let fields = columns.map(PostgreSQLSQL.identifier).joined(separator: ", ")
        let prefix = "ALTER TABLE " + target + " ADD CONSTRAINT " + PostgreSQLSQL.identifier(name) + " "
        let sql: String
        switch kind {
        case .index:
            guard ["btree", "hash", "gin", "gist", "spgist", "brin"].contains(method) else {
                throw DatabaseError.message("choose a supported index method")
            }
            sql =
                "CREATE " + (uniqueIndex ? "UNIQUE " : "") + "INDEX " + PostgreSQLSQL.identifier(name)
                + " ON " + target + " USING " + method + " (" + fields + ")"
        case .primaryKey: sql = prefix + "PRIMARY KEY (" + fields + ")" + deferred
        case .unique: sql = prefix + "UNIQUE (" + fields + ")" + deferred
        case .foreignKey:
            guard !referenceSchema.isEmpty, !referenceTable.isEmpty, referenceColumns.count == columns.count,
                ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL", "SET DEFAULT"].contains(onDelete),
                ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL", "SET DEFAULT"].contains(onUpdate)
            else {
                throw DatabaseError.message("select the same number of local and referenced columns and valid actions")
            }
            sql =
                prefix + "FOREIGN KEY (" + fields + ") REFERENCES "
                + PostgreSQLSQL.qualified(referenceSchema, referenceTable) + " ("
                + referenceColumns.map(PostgreSQLSQL.identifier).joined(separator: ", ") + ")"
                + " ON DELETE " + onDelete + " ON UPDATE " + onUpdate + deferred
        case .check:
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatabaseError.message("enter the check expression")
            }
            sql = prefix + "CHECK (" + expression + ")"
        }
        return .init(title: "create " + kind.rawValue, sql: sql, database: location.database, statements: [sql])
    }
    /// MariaDB/MySQL form of the same draft. `referenceTable` belongs to the same database.
    func mysqlPlan(database: String, table: String) throws -> SQLPlan {
        guard kind == .primaryKey || (!name.isEmpty && name.count <= 64 && !name.contains("\0")) else {
            throw DatabaseError.message("enter a constraint or index name up to 64 characters")
        }
        guard kind == .check || !columns.isEmpty else { throw DatabaseError.message("select at least one column") }
        let target = DatabaseSQL.qualified(database, table)
        let fields = columns.map(DatabaseSQL.identifier).joined(separator: ", ")
        let prefix = "ALTER TABLE " + target + " ADD CONSTRAINT " + DatabaseSQL.identifier(name) + " "
        let sql: String
        switch kind {
        case .index:
            sql =
                "CREATE " + (uniqueIndex ? "UNIQUE " : "") + "INDEX " + DatabaseSQL.identifier(name)
                + " ON " + target + " (" + fields + ");"
        case .primaryKey: sql = "ALTER TABLE " + target + " ADD PRIMARY KEY (" + fields + ");"
        case .unique: sql = prefix + "UNIQUE (" + fields + ");"
        case .foreignKey:
            let actions = ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL"]
            guard !referenceTable.isEmpty, referenceColumns.count == columns.count,
                actions.contains(onDelete), actions.contains(onUpdate)
            else {
                throw DatabaseError.message(
                    "select the same number of local and referenced columns. set default is not supported here")
            }
            sql =
                prefix + "FOREIGN KEY (" + fields + ") REFERENCES "
                + DatabaseSQL.qualified(database, referenceTable) + " ("
                + referenceColumns.map(DatabaseSQL.identifier).joined(separator: ", ") + ")"
                + " ON DELETE " + onDelete + " ON UPDATE " + onUpdate + ";"
        case .check:
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatabaseError.message("enter the check expression")
            }
            sql = prefix + "CHECK (" + expression + ");"
        }
        return .init(title: "create " + kind.rawValue, sql: sql, database: database)
    }
    private var deferred: String { deferrable ? " DEFERRABLE INITIALLY IMMEDIATE" : " NOT DEFERRABLE" }
}
