import Foundation

/// Prevents client-side routing and database-level commands; this is not a SQL permission sandbox.
enum DatabaseImportPolicy {
    static func validate(_ file: URL, engine: DatabaseEngine, database: String) throws {
        let cursor = try ImportSQLCursor(file)
        defer { try? cursor.close() }
        var prefix: [String] = [], previous = "", copyInput = false
        while let token = try cursor.token(engine: engine) {
            if token.client {
                guard engine.isPostgreSQL, ["restrict", "unrestrict"].contains(token.text) else {
                    throw DatabaseError.message("import cannot run client command \\" + token.text)
                }
                continue
            }
            if token.text == ";" && !token.quoted {
                if copyInput { try cursor.skipCopyData() }
                prefix = []
                previous = ""
                copyInput = false
                continue
            }
            let keyword = token.quoted ? "" : token.text.uppercased()
            if prefix.isEmpty && keyword == "USE" {
                prefix = ["USE"]
                continue
            }
            if prefix == ["USE"] {
                guard !engine.isPostgreSQL, token.text == database else {
                    throw DatabaseError.message(
                        "the file selects another database. import it into its original database")
                }
            }
            if prefix.count < 4 { prefix.append(keyword) }
            let command = prefix.filter { !["OR", "REPLACE"].contains($0) }
            if command.count >= 2, ["CREATE", "DROP", "ALTER"].contains(command[0]),
                command[1] == "DATABASE" || (!engine.isPostgreSQL && command[1] == "SCHEMA") {
                throw DatabaseError.message("import into an existing database cannot create, alter or drop databases")
            }
            if prefix.first == "COPY", previous == "FROM", keyword == "STDIN" { copyInput = true }
            previous = keyword
        }
    }
}

private final class ImportSQLCursor {
    struct Token {
        let text: String
        var quoted = false
        var client = false
    }
    private let input: FileHandle
    private var bytes: [UInt8] = []
    private var position = 0
    private var escapeString = false
    init(_ file: URL) throws { input = try FileHandle(forReadingFrom: file) }
    func close() throws { try input.close() }
    private func peek(_ distance: Int = 0) throws -> UInt8? {
        if position + distance >= bytes.count {
            bytes = Array(bytes.dropFirst(position))
            position = 0
            if let chunk = try input.read(upToCount: 65536) { bytes += chunk }
        }
        return position + distance < bytes.count ? bytes[position + distance] : nil
    }
    @discardableResult private func next() throws -> UInt8? {
        let value = try peek()
        if value != nil { position += 1 }
        return value
    }
    func token(engine: DatabaseEngine) throws -> Token? {
        while let byte = try peek() {
            if byte <= 32 {
                try next()
                continue
            }
            let following = try peek(1)
            if byte == 35 && !engine.isPostgreSQL || (byte == 45 && following == 45) {
                try line()
                continue
            }
            if byte == 47 && following == 42 {
                try next()
                try next()
                let marker = try peek() ?? 0
                if !engine.isPostgreSQL && [33, 77].contains(marker) {
                    try next()
                    if (try peek()) == 33 { try next() }
                    while let value = try peek(), (48...57).contains(value) { try next() }
                } else {
                    try comment()
                }
                continue
            }
            if byte == 42 && following == 47 {
                try next()
                try next()
                continue
            }
            if [39, 34, 96].contains(byte) { return try quoted(byte, engine: engine) }
            if byte == 36 && engine.isPostgreSQL, try dollarQuoted() { return .init(text: "", quoted: true) }
            if byte == 92 && engine.isPostgreSQL {
                try next()
                var name: [UInt8] = []
                while let value = try peek(), value > 32 { name.append(try next()!) }
                try line()
                return .init(text: try text(name), client: true)
            }
            if Self.word(byte) {
                var word: [UInt8] = []
                while let value = try peek(), Self.word(value) {
                    guard word.count < 4096 else { throw DatabaseError.message("an import identifier is too long") }
                    word.append(try next()!)
                }
                let value = try text(word)
                let delimiter = try peek()
                escapeString = engine.isPostgreSQL && value.uppercased() == "E" && delimiter == 39
                return .init(text: value)
            }
            try next()
            return .init(text: String(UnicodeScalar(byte)))
        }
        return nil
    }
    private func text(_ bytes: [UInt8]) throws -> String {
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw DatabaseError.message("import requires UTF-8 SQL")
        }
        return value
    }
    private static func word(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            || [95, 36].contains(byte) || byte >= 128
    }
    private func line() throws {
        while let byte = try next(), byte != 10 {}
    }
    private func comment() throws {
        var depth = 1
        while let byte = try next() {
            let following = try peek()
            if byte == 47 && following == 42 {
                try next()
                depth += 1
            }
            if byte == 42 && following == 47 {
                try next()
                depth -= 1
            }
            if depth == 0 { return }
        }
        throw DatabaseError.message("the import contains an unfinished SQL comment")
    }
    private func quoted(_ quote: UInt8, engine: DatabaseEngine) throws -> Token {
        try next()
        var name: [UInt8] = []
        let identifier = quote != 39
        let escaped = !engine.isPostgreSQL || escapeString
        escapeString = false
        while let byte = try next() {
            if byte == quote {
                if (try peek()) == quote {
                    try next()
                } else {
                    return .init(text: identifier ? try text(name) : "", quoted: true)
                }
            } else if byte == 92 && quote == 39 && escaped {
                try next()
                continue
            }
            if identifier {
                guard name.count < 4096 else { throw DatabaseError.message("an import identifier is too long") }
                name.append(byte)
            }
        }
        throw DatabaseError.message("the import contains an unfinished SQL string or identifier")
    }
    private func dollarQuoted() throws -> Bool {
        var tag: [UInt8] = [36], distance = 1
        while let byte = try peek(distance),
            byte == 95 || (65...90).contains(byte) || (97...122).contains(byte)
                || (distance > 1 && (48...57).contains(byte)) {
            tag.append(byte)
            distance += 1
            guard distance <= 128 else { return false }
        }
        guard try peek(distance) == 36 else { return false }
        tag.append(36)
        for _ in tag { try next() }
        while try peek() != nil {
            var matches = true
            for (index, byte) in tag.enumerated() where try peek(index) != byte {
                matches = false
                break
            }
            if matches {
                for _ in tag { try next() }
                return true
            }
            try next()
        }
        throw DatabaseError.message("the import contains an unfinished dollar-quoted body")
    }
    func skipCopyData() throws {
        try line()
        var prefix: [UInt8] = [], count = 0
        while let byte = try next() {
            if byte == 10 {
                if prefix == [92, 46] || prefix == [92, 46, 13] { return }
                prefix = []
                count = 0
            } else {
                if count < 4 { prefix.append(byte) }
                count += 1
            }
        }
        throw DatabaseError.message("the import contains unfinished COPY data")
    }
}
