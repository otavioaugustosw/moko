import Foundation

extension WorkspaceModel {
    func phpConnection(for project: PHPProject? = nil) -> DatabaseConnection? {
        guard let project = project ?? phpServer.projects.active, let id = project.connectionProfileID,
            let profile = profiles.items.first(where: { $0.id == id })
        else { return nil }
        let secret = id == profiles.selectedID ? password : Credentials.read(profile.credentialAccount) ?? ""
        var connection = profile.connection(password: secret)
        connection.defaultDatabase = project.database ?? profile.database
        return connection
    }
    static func query(_ sql: String, connection: DatabaseConnection) -> CommandResult {
        let response = connection.execute(sql, multiple: true, maxRows: 10000)
        let output =
            response.succeeded
            ? response.results.flatMap { result in
                result.rows.indices.map { row in
                    result.fields.indices.map { result.text(row, $0) ?? "" }.joined(separator: "\t")
                }
            }.joined(separator: "\n") : response.error
        return .init(code: Int32(response.code), output: output)
    }
    func query(
        _ sql: String, password secret: String, host: String, port: String, user: String, localSocket: Bool = false
    ) -> CommandResult {
        guard !PreviewRuntime.isActive else { return .init(code: 1, output: "preview") }
        if !localSocket {
            var connection = currentConnection
            connection.host = host
            connection.port = port
            connection.user = user
            connection.password = secret
            return Self.query(sql, connection: connection)
        }
        var code: Int32 = 1
        let output = (localSocket ? "localhost" : host).withCString { hostname in
            user.withCString { username in
                secret.withCString { password in
                    sql.withCString { query in
                        if localSocket {
                            return "/tmp/mysql.sock".withCString {
                                nativeQuery(hostname, 0, username, password, $0, query, &code)
                            }
                        }
                        return nativeQuery(hostname, UInt32(port) ?? 3306, username, password, nil, query, &code)
                    }
                }
            }
        }
        guard let output else { return .init(code: 1, output: "could not prepare the connection.") }
        defer { nativeFree(output) }
        return .init(code: code, output: String(cString: output))
    }
    func recoverLocalServices() {
        for profile in profiles.items where profile.managed {
            let secret = Credentials.read(profile.credentialAccount, allowInteraction: false) ?? ""
            if profile.engine.isPostgreSQL {
                postgresql.port = profile.port
                postgresql.recover(secret: secret)
            } else if RuntimePaths.installedMariaDB != nil {
                managedDatabase.port = profile.port
                managedDatabase.recover(secret: secret)
            }
        }
    }
}
