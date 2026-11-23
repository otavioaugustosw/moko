import Foundation
import PostgresNative

struct SQLQueryOptions {
    var parameters: [String?]?
    var job: SQLQueryJob?
    var statements: [String]?
}

final class SQLQueryJob {
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private var cancelled = false
    private var mysqlCancel: (() -> Void)?

    func mysqlLifecycle(_ identifier: UInt64, connection: DatabaseConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if identifier == 0 {
            mysqlCancel = nil
            return true
        }
        guard !cancelled else { return false }
        mysqlCancel = { _ = connection.execute("KILL QUERY \(identifier)") }
        return true
    }
    func attach(_ connection: OpaquePointer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        handle = PQcancelCreate(connection)
        return true
    }
    func detach() {
        lock.lock()
        defer { lock.unlock() }
        if let handle { PQcancelFinish(handle) }
        handle = nil
    }
    func cancel() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.cancelled = true
            if let handle = self.handle { PQcancelBlocking(handle) }
            self.mysqlCancel?()
        }
    }
}
