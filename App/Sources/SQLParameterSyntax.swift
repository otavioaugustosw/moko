import Foundation

enum SQLParameterSyntax {
    enum Kind { case identifier, quotedIdentifier, literal, comment }
    struct Token {
        let range: NSRange
        let text: String
        let kind: Kind
        var name: String {
            kind == .quotedIdentifier
                ? String(text.dropFirst().dropLast()).replacingOccurrences(of: "``", with: "`") : text
        }
    }
    struct Completion {
        let range: NSRange
        let prefix: String
        let suggestions: [String]
    }
    static func tokens(_ sql: String) -> [Token] {
        let units = Array(sql.utf16)
        var position = 0, result: [Token] = []
        while position < units.count {
            let start = position, unit = units[position]
            var kind: Kind?
            if unit == 35
                || (unit == 45 && position + 2 < units.count && units[position + 1] == 45
                    && units[position + 2] <= 32) {
                kind = .comment
                while position < units.count && ![10, 13].contains(units[position]) { position += 1 }
            } else if unit == 47 && position + 1 < units.count && units[position + 1] == 42 {
                kind = .comment
                position += 2
                while position + 1 < units.count && !(units[position] == 42 && units[position + 1] == 47) {
                    position += 1
                }
                position = min(units.count, position + 2)
            } else if [39, 34, 96].contains(unit) {
                kind = unit == 96 ? .quotedIdentifier : .literal
                position = quotedEnd(units, start: start)
            } else if identifier(unit, first: true) {
                kind = .identifier
                position += 1
                while position < units.count && identifier(units[position], first: false) { position += 1 }
            } else {
                position += 1
            }
            if let kind {
                result.append(
                    .init(
                        range: NSRange(location: start, length: position - start),
                        text: String(decoding: units[start..<position], as: UTF16.self), kind: kind))
            }
        }
        return result
    }
    static func highlights(_ sql: String, parameters: [String]) -> [NSRange] {
        let names = Set(parameters.filter { !$0.isEmpty }.map { $0.lowercased() })
        return tokens(sql).filter {
            ($0.kind == .identifier || $0.kind == .quotedIdentifier) && names.contains($0.name.lowercased())
        }.map(\.range)
    }
    static func completion(_ sql: String, caret: Int, parameters: [String]) -> Completion? {
        guard caret > 0, caret <= sql.utf16.count,
            let token = tokens(sql).first(where: { caret > $0.range.location && caret <= NSMaxRange($0.range) }),
            token.kind == .identifier
        else { return nil }
        let range = NSRange(location: token.range.location, length: caret - token.range.location)
        let prefix = (sql as NSString).substring(with: range)
        let suggestions = Set(
            parameters.filter {
                !$0.isEmpty && $0.lowercased().hasPrefix(prefix.lowercased()) && $0.lowercased() != prefix.lowercased()
            }
        ).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return suggestions.isEmpty ? nil : .init(range: range, prefix: prefix, suggestions: suggestions)
    }
    private static func identifier(_ unit: UInt16, first: Bool) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return unit == 95 || unit == 36 || CharacterSet.letters.contains(scalar)
            || (!first && CharacterSet.decimalDigits.contains(scalar))
    }
    private static func quotedEnd(_ units: [UInt16], start: Int) -> Int {
        let quote = units[start]
        var position = start + 1
        while position < units.count {
            let unit = units[position]
            position += 1
            if unit == quote {
                if position < units.count && units[position] == quote { position += 1 } else { break }
            } else if unit == 92 && quote != 96 {
                position = min(units.count, position + 1)
            }
        }
        return position
    }
}
