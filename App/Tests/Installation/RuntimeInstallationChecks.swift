import Foundation

@MainActor @main
struct RuntimeInstallationChecks {
    static func main() async {
        do {
            let fixture = try InstallationFixture()
            try await rejectedDownloads(fixture)
            try await cancelledDownload(fixture)
            try await installationAndRemoval(fixture)
            try await activationRollback(fixture)
            try await stagingRecovery(fixture)
            print("Installation: \(fixture.checks) real HTTPS, integrity, activation, recovery and removal checks passed.")
        } catch {
            print("Installation failed: " + error.localizedDescription)
            exit(1)
        }
    }
    private static func rejectedDownloads(_ fixture: InstallationFixture) async throws {
        try fixture.publish()
        try Data(repeating: 0, count: 64).write(to: fixture.root.appendingPathComponent("catalog.sig"))
        let invalidCatalog = fixture.model("invalid-catalog")
        await invalidCatalog.refresh()
        try fixture.require(invalidCatalog.packages.isEmpty && !invalidCatalog.error.isEmpty, "invalid signature accepted")
        try fixture.requireClean("invalid-catalog")
        for (path, expected) in [
            ("corrupt.dmg", "checksum"), ("short.dmg", "size"), ("missing.dmg", "unavailable"),
            ("redirect.dmg", "unavailable"),
        ] {
            try fixture.publish(path: path)
            let model = fixture.model(path)
            try await fixture.install(model)
            try fixture.require(model.error.contains(expected), "incorrect rejection of " + path + ": " + model.error)
            try fixture.require(model.installed == nil, "bad download was installed")
            try fixture.requireClean(path)
        }
        try fixture.publish()
        let production = fixture.model("production", production: true)
        try await fixture.install(production)
        try fixture.require(production.error.contains("notarization"), "public installer accepted an ad-hoc package")
        try fixture.requireClean("production")
        let running = fixture.model("running")
        try await fixture.install(running, inactive: { false })
        try fixture.require(running.error.contains("stop mariadb"), "active service was not protected")
        try fixture.requireClean("running")
        let pidFolder = fixture.root.appendingPathComponent("live-pid-data")
        try RuntimePaths.privateDirectory(pidFolder)
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: pidFolder.appendingPathComponent("server.pid"))
        let owned = fixture.model("live-pid")
        try await fixture.install(owned)
        try fixture.require(owned.error.contains("another moko instance"), "live runtime PID was not protected")
        try fixture.requireClean("live-pid")
    }
    private static func cancelledDownload(_ fixture: InstallationFixture) async throws {
        try fixture.publish(path: "slow.dmg")
        let model = fixture.model("cancelled")
        await model.refresh()
        guard let package = model.packages.first else { throw DatabaseError.message(model.error) }
        model.install(package)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && model.progress == 0 && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try fixture.require(model.busy && model.progress > 0, "slow download did not begin")
        model.cancel()
        try await fixture.wait(model)
        try fixture.require(model.error == "installation cancelled", "cancelled download was not handled")
        try fixture.requireClean("cancelled")
    }
    private static func installationAndRemoval(_ fixture: InstallationFixture) async throws {
        try fixture.publish()
        let model = fixture.model("installed")
        let data = fixture.root.appendingPathComponent("installed-data")
        try RuntimePaths.privateDirectory(data)
        let marker = data.appendingPathComponent("preserved.fixture")
        try Data("existing fixture data".utf8).write(to: marker)
        try await fixture.install(model)
        try fixture.require(model.error.isEmpty && model.installed?.version == "11.8.9", "installation failed: " + model.error)
        let folder = fixture.root.appendingPathComponent("installed")
        let payload = folder.appendingPathComponent("mariadb-11.8.9-arm64/MariaDB.runtime/Contents/Resources/Runtime/MariaDB")
        try fixture.require(
            FileManager.default.isExecutableFile(atPath: payload.appendingPathComponent("bin/mariadbd").path),
            "installed server executable is missing")
        try fixture.require(!FileManager.default.fileExists(atPath: data.appendingPathComponent("server.pid").path),
                            "installing the component started a service")
        let reloaded = fixture.model("installed")
        try fixture.require(reloaded.installed?.id == model.installed?.id, "installation did not survive reload")
        try await runInstalledServices(fixture, payload: payload)
        try fixture.publish(version: "12.0.1")
        try await fixture.install(model)
        try fixture.require(model.error.contains("major database upgrade"), "major upgrade was not blocked")
        try fixture.publish()
        try await fixture.install(model)
        try fixture.require(model.error.contains("already installed"), "installed version was not protected")
        try model.remove()
        try fixture.require(model.installed == nil, "component removal failed")
        try fixture.require(try Data(contentsOf: marker) == Data("existing fixture data".utf8), "removal changed database data")
        try fixture.requireClean("installed")
    }
    private static func runInstalledServices(_ fixture: InstallationFixture, payload: URL) async throws {
        print("Installation: downloaded and activated; validating the installed MariaDB services.")
        fflush(stdout)
        let environment = ProcessInfo.processInfo.environment
        guard let script = environment["MOKO_INSTALLATION_SCRIPT"], let app = environment["MOKO_INSTALLATION_APP"] else {
            throw DatabaseError.message("missing runtime validation inputs")
        }
        let result = await Task.detached {
            execute("/usr/bin/python3", [script, app, "--optional-runtime", payload.path])
        }.value
        try result.output.write(to: fixture.root.appendingPathComponent("Service Validation.log"), atomically: true, encoding: .utf8)
        try fixture.require(result.code == 0, "installed runtime checks failed: " + result.output.suffix(2500))
        print(result.output)
    }
    private static func activationRollback(_ fixture: InstallationFixture) async throws {
        let name = "rollback", identifier = "mariadb-stable-arm64"
        let folder = fixture.root.appendingPathComponent(name), target = folder.appendingPathComponent(identifier)
        try RuntimePaths.privateDirectory(target)
        let marker = target.appendingPathComponent("original.fixture")
        try Data("original component".utf8).write(to: marker)
        let active = folder.appendingPathComponent("active.json")
        try JSONEncoder().encode(InstalledRuntime(id: identifier, version: "11.8.8", compatibilityLine: "11.8")).write(to: active)
        let model = fixture.model(name)
        try FileManager.default.removeItem(at: active)
        // A directory at the record path forces an atomic-write failure after copying.
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: false)
        try fixture.publish(identifier: identifier)
        try await fixture.install(model)
        try fixture.require(!model.error.isEmpty, "activation failure was not reported")
        try fixture.require(model.installed?.version == "11.8.8", "failed activation changed the installed record")
        try fixture.require(try Data(contentsOf: marker) == Data("original component".utf8), "rollback lost the previous component")
        try FileManager.default.removeItem(at: active)
        try fixture.requireClean(name)
    }
    private static func stagingRecovery(_ fixture: InstallationFixture) async throws {
        let folder = fixture.root.appendingPathComponent("recovery")
        let abandoned = folder.appendingPathComponent(".install-abandoned")
        let live = folder.appendingPathComponent(".install-live")
        for staging in [abandoned, live] {
            try RuntimePaths.privateDirectory(staging)
            try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-120)], ofItemAtPath: staging.path)
        }
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: live.appendingPathComponent("owner.pid"))
        let model = fixture.model("recovery")
        let deadline = Date().addingTimeInterval(5)
        while FileManager.default.fileExists(atPath: abandoned.path) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try fixture.require(!FileManager.default.fileExists(atPath: abandoned.path), "abandoned staging was not recovered")
        try fixture.require(FileManager.default.fileExists(atPath: live.path), "a live installation staging directory was removed")
        withExtendedLifetime(model) {}
    }
}
