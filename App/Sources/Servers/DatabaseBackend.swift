import Foundation

extension WorkspaceModel {
    var usesBundledDatabase: Bool { profiles.selected.managed }
    var controlsExistingMySQL: Bool { !usesBundledDatabase && ExistingMySQLService.available(for: currentConnection) }
    var healthSQL: String {
        if engine.isPostgreSQL {
            return """
                SELECT current_setting('port'), version(), current_user, COALESCE(inet_server_addr()::text,'localhost'), '',
                  EXTRACT(EPOCH FROM now()-pg_postmaster_start_time())::bigint::text;
                SELECT 'Uptime', EXTRACT(EPOCH FROM now()-pg_postmaster_start_time())::bigint::text;
                """
        }
        return "SELECT @@port, @@version, CURRENT_USER(), @@hostname, @@socket; "
            + "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_connected');"
    }
    var sessionsSQL: String {
        if engine.isPostgreSQL {
            return """
                SELECT json_build_object('id',pid,'user',COALESCE(usename,''),'host',COALESCE(client_addr::text,''),
                  'database',COALESCE(datname,''),'command',COALESCE(state,''),'seconds',
                  GREATEST(EXTRACT(EPOCH FROM now()-query_start)::bigint,0),'state',COALESCE(wait_event,''))::text
                  FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend' ORDER BY pid
                """
        }
        return Self.sessionSQL
    }
    func selectProfile(_ id: UUID) {
        guard !working else { return }
        profiles.select(id)
        let profile = profiles.selected
        backend = profile.managed ? (profile.engine.isPostgreSQL ? "postgresql" : "bundled") : "external"
        configureBackend()
        resetConnection()
        databaseBrowser.configure(nil)
        refresh()
        notify?()
    }
    func selectBackend(_ value: String) {
        if value == "postgresql" {
            selectProfile(ConnectionProfile.local(.postgresql).id)
        } else if value == "bundled" {
            selectProfile(ConnectionProfile.local(.mariadb).id)
        } else if let profile = profiles.items.first(where: { !$0.managed }) {
            selectProfile(profile.id)
        } else {
            let id = UUID()
            profiles.save(
                .init(
                    id: id, name: "existing server", engine: .mysql, managed: false,
                    host: "127.0.0.1", port: "3306", user: "root", database: "", tlsMode: "prefer",
                    rootCertificate: "", credentialAccount: "moko.profile." + id.uuidString))
            selectProfile(id)
        }
    }
    func configureBackend(allowCredentialInteraction: Bool = true) {
        let profile = profiles.selected
        host = profile.host
        port = profile.port
        username = profile.user
        password = Credentials.read(profile.credentialAccount, allowInteraction: allowCredentialInteraction) ?? ""
        managesServer = profile.managed
        if profile.managed {
            if profile.engine.isPostgreSQL && !postgresql.running && !postgresql.busy { postgresql.port = profile.port }
            if !profile.engine.isPostgreSQL && !managedDatabase.running && !managedDatabase.busy {
                managedDatabase.port = profile.port
            }
        }
        if profile.managed {
            if profile.engine.isPostgreSQL {
                postgresql.recover(secret: password)
                localServiceRunning = { [weak self] in self?.postgresql.running == true }
            } else {
                managedDatabase.recover(secret: password)
                localServiceRunning = { [weak self] in self?.managedDatabase.running == true }
            }
        } else {
            localServiceRunning = { [weak self] in
                self?.controlsExistingMySQL == true && ExistingMySQLService.running()
            }
        }
    }
    func controlService(_ engine: DatabaseEngine, command: String, completed: ((Bool) -> Void)? = nil) {
        if let profile = profiles.items.first(where: { $0.managed && $0.engine == engine }) {
            if engine.isPostgreSQL && !postgresql.running && !postgresql.busy { postgresql.port = profile.port }
            if !engine.isPostgreSQL && !managedDatabase.running && !managedDatabase.busy {
                managedDatabase.port = profile.port
            }
        }
        let update: (Result<String, Error>) -> Void = { result in
            switch result {
            case let .success(secret):
                if self.profiles.selected.managed && self.engine == engine {
                    if command != "stop" { self.password = secret }
                    self.refresh()
                }
                self.add(engine.rawValue + " " + (command == "stop" ? "stopped" : "started"))
                completed?(true)
            case let .failure(error):
                self.notice = error.localizedDescription
                completed?(false)
            }
            self.notify?()
        }
        if engine.isPostgreSQL {
            postgresql.control(command, completed: update)
        } else if RuntimePaths.installedMariaDB != nil || command == "stop" && managedDatabase.running {
            managedDatabase.control(command, completed: update)
        } else {
            notice = "install the optional mariadb component before starting it. existing data was preserved"
            page = "settings"
            settingsSection = "components"
            completed?(false)
        }
    }
    func controlBundled(_ command: String, completed: ((Bool) -> Void)?) {
        serviceOperation = command
        working = true
        light = .yellow
        controlService(engine, command: command) { success in
            self.working = false
            self.serviceOperation = nil
            self.refresh()
            completed?(success)
        }
    }
    func controlExisting(_ operation: ExistingMySQLService.Operation, completed: ((Bool) -> Void)?) {
        working = true
        serviceOperation = operation.rawValue
        notice = ""
        ExistingMySQLService.perform(operation, connection: currentConnection) { result in
            self.working = false
            self.serviceOperation = nil
            if result.code != 0 { self.notice = result.output } else {
                self.add("existing mysql " + operation.rawValue + " completed")
            }
            self.refresh()
            self.notify?()
            completed?(result.code == 0)
        }
    }
    func shutdown(completed: @escaping () -> Void) {
        services.shutdown(completed: completed)
    }
}
