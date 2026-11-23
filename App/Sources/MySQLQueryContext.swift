import Foundation

final class MySQLQueryContext {
    let connection: DatabaseConnection
    let job: SQLQueryJob?
    init(connection: DatabaseConnection, job: SQLQueryJob?) {
        self.connection = connection
        self.job = job
    }
}
