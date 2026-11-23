import Foundation

// Disposable UI fixture. The marker and unique name prevent touching existing databases.
enum InterfaceFixture {
    struct State: Codable {
        let database: String
        let token: String
    }
    static func run(_ connection: DatabaseConnection, mode: String, stateURL: URL) -> Bool {
        func execute(_ sql: String, database: String = "", multiple: Bool = false) throws -> SQLResponse {
            let result = connection.execute(sql, database: database, multiple: multiple)
            guard result.succeeded else { throw DatabaseError.message("fixture: \(result.error) (\(result.code))") }
            return result
        }
        do {
            if mode == "create" {
                guard !FileManager.default.fileExists(atPath: stateURL.path) else {
                    throw DatabaseError.message("fixture existente; use status ou remove antes de criar outra")
                }
                let state = State(
                    database: "moko_ui_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                    token: UUID().uuidString)
                _ = try execute("CREATE DATABASE \(DatabaseSQL.identifier(state.database)) CHARACTER SET utf8mb4")
                do {
                    try FileManager.default.createDirectory(
                        at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
                    _ = try execute(
                        """
                        CREATE TABLE __moko_fixture (token varchar(80) NOT NULL);
                        INSERT INTO __moko_fixture VALUES (\(DatabaseSQL.literal(state.token)));
                        CREATE TABLE categorias (id int NOT NULL PRIMARY KEY, nome varchar(60) NOT NULL);
                        INSERT INTO categorias VALUES (1,'categoria de teste'), (2,'outra categoria');
                        CREATE TABLE itens (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
                          nome varchar(80) NOT NULL DEFAULT '', data date NOT NULL DEFAULT '2026-10-09',
                          horario time(6) NOT NULL DEFAULT '19:30:10.123456', categoria_id int DEFAULT 1,
                          contador int NOT NULL DEFAULT 0,
                          ativo tinyint(1) NOT NULL DEFAULT 1, notas text DEFAULT NULL,
                          atualizado timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                          CONSTRAINT fk_categoria FOREIGN KEY (categoria_id) REFERENCES categorias(id)) ENGINE=InnoDB;
                        INSERT INTO itens(nome,contador) VALUES ('registro de teste',1), ('segundo registro',2);
                        """, database: state.database, multiple: true)
                    print("fixture criada: \(state.database)")
                    return true
                } catch {
                    _ = connection.execute("DROP DATABASE \(DatabaseSQL.identifier(state.database))")
                    try? FileManager.default.removeItem(at: stateURL)
                    throw error
                }
            }
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
            guard state.database.hasPrefix("moko_ui_"), state.database.count == 40,
                state.database.dropFirst(8).allSatisfy({ $0.isHexDigit })
            else { throw DatabaseError.message("invalid fixture name") }
            let marker = try execute("SELECT token FROM __moko_fixture LIMIT 1", database: state.database)
            guard marker.results.first?.text(0, 0) == state.token else {
                throw DatabaseError.message("unknown fixture")
            }
            switch mode {
            case "update":
                _ = try execute("UPDATE itens SET contador=contador+1 WHERE id=1", database: state.database)
                print("fixture: contador atualizado")
            case "status":
                let result = try execute(
                    "SELECT nome,contador,data,horario,categoria_id FROM itens WHERE id=1; SHOW COLUMNS FROM itens LIKE 'contador'",
                    database: state.database, multiple: true)
                print(
                    "fixture: nome=\(result.results[0].text(0, 0) ?? "—"), contador=\(result.results[0].text(0, 1) ?? "—"), tipo=\(result.results[1].text(0, 1) ?? "—")"
                )
                print(
                    "fixture: data=\(result.results[0].text(0, 2) ?? "—"), horario=\(result.results[0].text(0, 3) ?? "—"), categoria=\(result.results[0].text(0, 4) ?? "—")"
                )
            case "remove":
                _ = try execute("DROP DATABASE \(DatabaseSQL.identifier(state.database))")
                try FileManager.default.removeItem(at: stateURL)
                print("fixture da interface removida")
            default: throw DatabaseError.message("use create, update, status ou remove")
            }
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}
