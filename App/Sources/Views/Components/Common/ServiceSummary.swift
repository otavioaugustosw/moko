import SwiftUI

struct ServiceSummary: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject var php: PHPServer
    @ObservedObject var postgres: ManagedPostgreSQL
    @ObservedObject var mariadb: ManagedDatabase
    init(server: WorkspaceModel, php: PHPServer) {
        self.server = server
        self.php = php
        self.postgres = server.postgresql
        self.mariadb = server.managedDatabase
    }
    var body: some View {
        let optional = RuntimePaths.installedMariaDB != nil
        let count = (postgres.running ? 1 : 0) + (mariadb.running ? 1 : 0) + (php.running ? 1 : 0)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count) of \(optional ? 3 : 2) local services running").font(.callout)
            Text("php: \(php.busy ? "changing state" : (php.running ? "running" : "stopped"))")
                .font(.caption).foregroundStyle(MokoTheme.secondaryInk)
        }.accessibilityElement(children: .combine)
    }
}
