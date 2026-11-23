#if DEBUG
    import SwiftUI

    @available(macOS 26.0, *)
    enum PreviewFixtures {
        static let preferences: UserDefaults = {
            let testing = ProcessInfo.processInfo.environment["MOKO_UI_TESTING"] == "1"
            let name =
                testing
                ? "moko.interface." + String(ProcessInfo.processInfo.processIdentifier)
                : "com.otavioaugustosw.moko.previews"
            let preferences = UserDefaults(suiteName: name) ?? .standard
            if testing { preferences.removePersistentDomain(forName: name) }
            preferences.set(true, forKey: "moko.onboardingCompleted")
            return preferences
        }()
        static let columns: [DatabaseColumn] = [
            column("id", type: "int", key: "PRI", extra: "auto_increment"),
            column("nome", type: "varchar(80)"),
            column("data", type: "date"),
            column("horario", type: "time"),
            column("notas", type: "text", nullable: true),
        ]
        static func column(
            _ name: String, type: String, key: String = "", extra: String = "", nullable: Bool = false
        ) -> DatabaseColumn {
            .init(
                name: name, type: type, nullable: nullable, key: key, defaultValue: nil,
                extra: extra, collation: "", comment: "")
        }
        static let result = SQLResult(
            fields: columns.map { .init(name: $0.name, type: 0, binary: false) },
            rows: [
                ["1", "registro de exemplo", "2026-10-11", "19:30:00", nil],
                ["2", "another record", "2026-10-12", "09:00:00", "note"],
            ].map {
                $0.map { $0.map { Data($0.utf8).hexString } }
            }, affected: 0, truncated: false, warnings: 0)
        static func server(page: String = "overview", running: Bool = true) -> WorkspaceModel {
            let model = WorkspaceModel(
                phpServer: PHPServer(preferences: preferences), profiles: ConnectionProfiles(preferences: preferences))
            model.page = page
            model.running = running
            model.connected = running
            model.light = running ? .green : .red
            model.host = "127.0.0.1"
            model.port = "3306"
            model.username = "exemplo"
            model.account = "exemplo@localhost"
            model.version = "9.4.0"
            model.actualPort = "3306"
            model.connections = "2"
            model.serverName = "localhost"
            model.managesServer = true
            model.events = [Event(text: "server started"), Event(text: "connection tested")]
            model.sessions = [
                .init(
                    id: 12, user: "exemplo", host: "localhost", database: "exemplo",
                    command: "Sleep", seconds: 8, state: ""),
            ]
            populate(model.databaseBrowser)
            return model
        }
        static func browser(engine: DatabaseEngine = .mariadb) -> DatabaseModel {
            let model = DatabaseModel()
            populate(model)
            model.connection = .init(
                host: "127.0.0.1", port: engine.localPort, user: "fixture", password: "", engine: engine)
            if engine.isPostgreSQL {
                model.schemas = ["public", "shop"]
                model.schema = "shop"
                model.columns = columns.map { column in
                    .init(
                        name: column.name, type: column.type == "int" ? "integer" : column.type,
                        nullable: column.nullable, key: column.key, defaultValue: column.defaultValue,
                        extra: column.extra.isEmpty ? "" : "IDENTITY DEFAULT auto_increment",
                        collation: column.collation,
                        comment: column.comment, engine: engine)
                }
            }
            return model
        }
        static func populate(_ model: DatabaseModel) {
            model.databases = ["exemplo"]
            model.database = "exemplo"
            model.tables = [.init(name: "registros", kind: "BASE TABLE", engine: "InnoDB", estimatedRows: "2")]
            model.table = "registros"
            model.columns = columns
            model.data = result
            model.ddl = "CREATE TABLE registros (id int PRIMARY KEY, nome varchar(80));"
            model.sql = "SELECT * FROM registros;"
            model.sqlResults = [result]
        }
        static func row(editing: Bool = false) -> RowDraft {
            .init(
                original: editing ? result.cells[0] : nil,
                values: Dictionary(
                    uniqueKeysWithValues: columns.enumerated().map {
                        ($0.element.name, CellDraft(text: editing ? result.text(0, $0.offset) ?? "" : "", mode: .value))
                    }))
        }
    }
#endif
