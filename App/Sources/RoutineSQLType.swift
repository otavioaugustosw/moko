import Foundation

enum RoutineSQLType {
    static let choices = [
        "int", "bigint", "smallint", "tinyint", "mediumint", "boolean", "decimal", "float", "double",
        "varchar", "char", "text", "mediumtext", "longtext", "date", "time", "datetime", "timestamp", "year",
        "json", "binary", "varbinary", "blob", "mediumblob", "longblob",
    ]
    static func name(_ definition: String) -> String {
        String(definition.lowercased().prefix { $0 != "(" && !$0.isWhitespace })
    }
    static func size(_ definition: String) -> String {
        guard let start = definition.firstIndex(of: "("), let end = definition.lastIndex(of: ")"), start < end else {
            return ""
        }
        return String(definition[definition.index(after: start)..<end])
    }
    static func defaultSize(_ name: String) -> String {
        switch name {
        case "varchar", "varbinary": "255"
        case "char", "binary": "1"
        case "decimal": "12,2"
        default: ""
        }
    }
    static func selecting(_ name: String, current: String) -> String {
        guard name != self.name(current) else { return current }
        let size = defaultSize(name)
        return name + (size.isEmpty ? "" : "(\(size))")
    }
    static func resizing(_ size: String, current: String) -> String {
        let suffix = current.lowercased().hasSuffix(" unsigned") ? " unsigned" : ""
        return name(current) + "(\(size))" + suffix
    }
}
