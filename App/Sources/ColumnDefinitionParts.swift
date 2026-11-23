import Foundation

struct ColumnDefinitionParts {
    struct Token {
        let text: String
        let range: Range<Int>
        var word: String { text.uppercased() }
    }
    let source: String
    var ranges = [String: Range<Int>]()
    var values = ColumnEditorValues()
    var generated = false
    func text(_ key: String) -> String? { ranges[key].map { String(Array(source)[$0]) } }
    init(_ source: String) {
        // SHOW CREATE wraps visibility in /*!80023 ... */. Normalize only the
        // known modifier, outside strings, so editing DEFAULT cannot swallow its
        // opening delimiter and leave a dangling closing comment behind.
        var characters = Array(source)
        for token in Self.tokens(source).reversed() {
            if let modifier = Self.visibilityComment(token.text) {
                characters.replaceSubrange(token.range, with: Array(modifier))
            }
        }
        let source = String(characters)
        self.source = source
        let tokens = Self.tokens(source)
        guard !tokens.isEmpty else { return }
        values.typeName = tokens[0].text.lowercased()
        values.parameters = ""
        values.defaultMode = .none
        var index = 1
        if tokens.indices.contains(index), tokens[index].text.hasPrefix("(") {
            values.parameters = String(tokens[index].text.dropFirst().dropLast())
            if ["enum", "set"].contains(values.typeName) {
                values.choicesText = Self.tokens(values.parameters).filter { $0.text.first == "'" }.map {
                    Self.unquote($0.text)
                }.joined(separator: "\n")
            }
            index += 1
        }
        ranges["type"] = 0..<tokens[index - 1].range.upperBound
        let boundaries: Set<String> = [
            "NOT", "NULL", "DEFAULT", "AUTO_INCREMENT", "UNSIGNED", "ZEROFILL", "COLLATE", "COMMENT", "VISIBLE",
            "INVISIBLE", "GENERATED", "AS", "VIRTUAL", "STORED", "ON", "CHARACTER", "COLUMN_FORMAT", "STORAGE", "SRID",
            "ENGINE_ATTRIBUTE", "SECONDARY_ENGINE_ATTRIBUTE", "PRIMARY", "UNIQUE", "REFERENCES", "CHECK",
        ]
        while index < tokens.count {
            let first = index, token = tokens[index]
            var key: String?
            switch token.word {
            case "UNSIGNED":
                values.unsigned = true
                key = "unsigned"
                index += 1
            case "ZEROFILL":
                values.zerofill = true
                key = "zerofill"
                index += 1
            case "AUTO_INCREMENT":
                values.autoIncrement = true
                key = "autoIncrement"
                index += 1
            case "NOT" where tokens.indices.contains(index + 1) && tokens[index + 1].word == "NULL":
                values.nullable = false
                key = "nullable"
                index += 2
            case "NULL":
                values.nullable = true
                key = "nullable"
                index += 1
            case "VISIBLE", "INVISIBLE":
                values.invisible = token.word == "INVISIBLE"
                key = "invisible"
                index += 1
            case "COLLATE" where tokens.indices.contains(index + 1):
                values.collation = tokens[index + 1].text
                key = "collation"
                index += 2
            case "COMMENT" where tokens.indices.contains(index + 1):
                values.comment = Self.unquote(tokens[index + 1].text)
                key = "comment"
                index += 2
            case "DEFAULT":
                key = "default"
                index += 1
                if index < tokens.count { index += 1 }
                while index < tokens.count && !boundaries.contains(tokens[index].word)
                    && !tokens[index].text.hasPrefix("/*") { index += 1 }
                let raw =
                    first + 1 < index
                    ? String(Array(source)[tokens[first + 1].range.lowerBound..<tokens[index - 1].range.upperBound])
                    : ""
                readDefault(raw)
            case "GENERATED", "AS":
                generated = true
                index += 1
            default: index += 1
            }
            if let key { ranges[key] = tokens[first].range.lowerBound..<tokens[index - 1].range.upperBound }
        }
    }
    private mutating func readDefault(_ raw: String) {
        if raw.uppercased() == "NULL" {
            values.defaultMode = .null
        } else if raw.first == "'" && raw.last == "'" {
            values.defaultMode = .value
            values.defaultText = Self.unquote(raw)
        } else if raw.uppercased().hasPrefix("CURRENT_TIMESTAMP") {
            values.defaultMode = .currentTimestamp
            values.defaultText = raw
        } else if raw.first == "(" {
            values.defaultMode = .expression
            values.defaultText = raw
        } else if Double(raw) != nil {
            values.defaultMode = .value
            values.defaultText = raw
        } else {
            values.defaultMode = .expression
            values.defaultText = raw
        }
    }
    static func visibilityComment(_ source: String) -> String? {
        guard source.hasPrefix("/*!"), source.hasSuffix("*/") else { return nil }
        let body = source.dropFirst(3).dropLast(2).drop(while: { $0.isNumber }).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return ["INVISIBLE", "VISIBLE"].contains(body.uppercased()) ? body : nil
    }
    static func tokens(_ source: String) -> [Token] {
        let characters = Array(source)
        var result = [Token](), position = 0
        while position < characters.count {
            if characters[position].isWhitespace || characters[position] == "," {
                position += 1
                continue
            }
            let start = position
            if position + 1 < characters.count, characters[position] == "/", characters[position + 1] == "*" {
                position += 2
                while position + 1 < characters.count
                    && !(characters[position] == "*" && characters[position + 1] == "/") { position += 1 }
                position = min(characters.count, position + 2)
            } else if ["'", "\"", "`"].contains(characters[position]) {
                position = endOfQuotedToken(characters, position: position)
            } else if characters[position] == "(" {
                var depth = 0
                var quote: Character?
                while position < characters.count {
                    let current = characters[position]
                    position += 1
                    if let quoted = quote {
                        if current == "\\" && position < characters.count {
                            position += 1
                        } else if current == quoted {
                            if position < characters.count && characters[position] == quoted {
                                position += 1
                            } else {
                                quote = nil
                            }
                        }
                    } else if ["'", "\"", "`"].contains(current) {
                        quote = current
                    } else if current == "(" {
                        depth += 1
                    } else if current == ")" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                }
            } else {
                while position < characters.count && !characters[position].isWhitespace
                    && !["(", "'", "\"", "`", ","].contains(characters[position]) { position += 1 }
            }
            if position == start { position += 1 }
            result.append(.init(text: String(characters[start..<position]), range: start..<position))
        }
        return result
    }
    private static func endOfQuotedToken(_ characters: [Character], position: Int) -> Int {
        var position = position
        let quote = characters[position]
        position += 1
        while position < characters.count {
            let current = characters[position]
            position += 1
            if current == "\\" && position < characters.count {
                position += 1
            } else if current == quote {
                if position < characters.count && characters[position] == quote { position += 1 } else { break }
            }
        }
        return position
    }
    static func unquote(_ source: String) -> String {
        guard source.first == "'", source.last == "'" else { return source }
        let characters = Array(source.dropFirst().dropLast())
        var result = "", i = 0
        while i < characters.count {
            let char = characters[i]
            i += 1
            if char == "\\", i < characters.count {
                let next = characters[i]
                i += 1
                switch next {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "0": result.append("\0")
                case "b": result.append("\u{8}")
                case "Z": result.append("\u{1a}")
                default: result.append(next)
                }
            } else if char == "'", i < characters.count, characters[i] == "'" {
                result.append("'")
                i += 1
            } else {
                result.append(char)
            }
        }
        return result
    }
}
