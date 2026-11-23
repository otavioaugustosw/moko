import Foundation

struct DatabaseTool {
    enum Kind { case postgresql, mariadb, mysql }
    let executable: URL
    let kind: Kind
    var pluginArguments: [String] {
        guard kind == .mariadb else { return [] }
        let root = executable.deletingLastPathComponent().deletingLastPathComponent()
        let plugins = root.appendingPathComponent("lib/plugin")
        return FileManager.default.fileExists(atPath: plugins.path) ? ["--plugin-dir=" + plugins.path] : []
    }
}

enum DatabaseTools {
    enum Operation { case exportSQL, importSQL }
    static let systemDirectories = [
        "/usr/local/mysql/bin", "/opt/homebrew/opt/mysql/bin", "/opt/homebrew/opt/mysql-client/bin",
        "/opt/homebrew/opt/mysql@8.4/bin", "/opt/homebrew/opt/mysql@8.0/bin",
        "/usr/local/opt/mysql/bin", "/usr/local/opt/mysql-client/bin",
        "/opt/homebrew/opt/mariadb/bin", "/opt/homebrew/opt/mariadb@11.8/bin", "/usr/local/opt/mariadb/bin",
    ].map { URL(fileURLWithPath: $0) }

    static func resolve(_ operation: Operation, engine: DatabaseEngine, archive: Bool = false) throws -> DatabaseTool {
        let tool = try locate(
            operation, engine: engine, archive: archive, postgres: RuntimePaths.root.appendingPathComponent("PostgreSQL"),
            mariadb: RuntimePaths.installedMariaDB, directories: systemDirectories)
        try RuntimePaths.validateInstalledExecutable(tool.executable)
        return tool
    }
    static func locate(
        _ operation: Operation, engine: DatabaseEngine, archive: Bool = false,
        postgres: URL, mariadb: URL?, directories: [URL]
    ) throws -> DatabaseTool {
        func tool(_ file: URL, _ kind: DatabaseTool.Kind) -> DatabaseTool? {
            FileManager.default.isExecutableFile(atPath: file.path) ? .init(executable: file, kind: kind) : nil
        }
        if engine.isPostgreSQL {
            let name = operation == .exportSQL ? "pg_dump" : (archive ? "pg_restore" : "psql")
            if let value = tool(postgres.appendingPathComponent("bin/" + name), .postgresql) { return value }
        } else {
            let mysql = operation == .exportSQL ? "mysqldump" : "mysql"
            let maria = operation == .exportSQL ? "mariadb-dump" : "mariadb"
            if engine == .mysql {
                for directory in directories {
                    if let value = tool(directory.appendingPathComponent(mysql), .mysql) { return value }
                }
            }
            if let mariadb, let value = tool(mariadb.appendingPathComponent("bin/" + maria), .mariadb) { return value }
            for directory in directories {
                if let value = tool(directory.appendingPathComponent(maria), .mariadb) { return value }
            }
        }
        throw DatabaseError.message(
            engine.isPostgreSQL
                ? "postgresql transfer tools are missing. reinstall moko."
                : "mysql/mariadb transfer tools were not found. install the matching client tools or the optional mariadb component.")
    }
}
