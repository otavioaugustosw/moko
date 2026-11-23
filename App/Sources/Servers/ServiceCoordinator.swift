import Foundation

/// Owns only moko's processes; connection selection is independent of service lifecycle.
final class ServiceCoordinator {
    let postgresql = ManagedPostgreSQL()
    let mariadb = ManagedDatabase()
    let php: PHPServer
    init(php: PHPServer) { self.php = php }
    func shutdown(completed: @escaping () -> Void) {
        php.stop { self.postgresql.shutdown { self.mariadb.shutdown(completed: completed) } }
    }
}
