import Foundation

enum PHPDatabaseExample {
    static func variables(_ connection: DatabaseConnection, database: String, password: String?) -> [String: String] {
        [
            "MOKO_DB_ENGINE": connection.engine.rawValue, "MOKO_DB_HOST": connection.host,
            "MOKO_DB_PORT": connection.port, "MOKO_DB_USER": connection.user,
            "MOKO_DB_DATABASE": database, "MOKO_DB_PASSWORD": password ?? "",
            "MOKO_DB_TLS_MODE": connection.tlsMode.isEmpty ? "prefer" : connection.tlsMode,
            "MOKO_DB_ROOT_CERTIFICATE": connection.rootCertificate,
        ]
    }
    static func environment(_ connection: DatabaseConnection, database: String, password: String?) -> String {
        let values = variables(connection, database: database, password: password)
        return values.keys.sorted().map { key in
            let value = values[key]!.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
            return key + "='" + value + "'"
        }.joined(separator: "\n") + "\n"
    }
    static func pdo(_ engine: DatabaseEngine) -> String {
        let driver = engine.isPostgreSQL ? "pgsql" : "mysql"
        return """
            <?php
            $dsn = '\(driver):host=' . getenv('MOKO_DB_HOST')
                . ';port=' . getenv('MOKO_DB_PORT')
                . ';dbname=' . getenv('MOKO_DB_DATABASE')\(engine.isPostgreSQL ? ";" : " . ';charset=utf8mb4';")
            $options = [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_EMULATE_PREPARES => false,
            ];
            \(tls(engine))
            """
    }
    private static func tls(_ engine: DatabaseEngine) -> String {
        if engine.isPostgreSQL {
            return """
                $dsn .= ';sslmode=' . (getenv('MOKO_DB_TLS_MODE') ?: 'prefer');
                if ($ca = getenv('MOKO_DB_ROOT_CERTIFICATE')) { $dsn .= ';sslrootcert=' . $ca; }
                $pdo = new PDO($dsn, getenv('MOKO_DB_USER'), getenv('MOKO_DB_PASSWORD'), $options);
                """
        }
        return """
            $mode = getenv('MOKO_DB_TLS_MODE') ?: 'prefer';
            $options[Pdo\\Mysql::ATTR_SSL_CIPHER] = 'DEFAULT';
            $options[Pdo\\Mysql::ATTR_SSL_CA] = getenv('MOKO_DB_ROOT_CERTIFICATE') ?: '';
            $options[Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT] = $mode === 'verify-full';
            try {
                $pdo = new PDO($dsn, getenv('MOKO_DB_USER'), getenv('MOKO_DB_PASSWORD'), $options);
            } catch (PDOException $error) {
                if ($mode !== 'prefer' || !in_array($error->errorInfo[1] ?? 0, [2026, 2006], true)) { throw $error; }
                unset($options[Pdo\\Mysql::ATTR_SSL_CIPHER], $options[Pdo\\Mysql::ATTR_SSL_CA],
                    $options[Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT]);
                $pdo = new PDO($dsn, getenv('MOKO_DB_USER'), getenv('MOKO_DB_PASSWORD'), $options);
            }
            """
    }
}
