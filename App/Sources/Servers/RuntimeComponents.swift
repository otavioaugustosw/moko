import Combine
import Foundation

@MainActor
final class RuntimeComponents: ObservableObject {
    static let shared = RuntimeComponents()
    /// True when this build ships MariaDB inside the application instead of as a download.
    nonisolated static var included: Bool { RuntimePaths.includedMariaDB != nil }
    enum Availability { case unchecked, available, unavailable }
    @Published private(set) var availability: Availability = .unchecked
    @Published private(set) var packages: [RuntimePackage] = []
    @Published private(set) var busy = false
    @Published private(set) var phase = ""
    @Published private(set) var progress = 0.0
    @Published private(set) var installed: InstalledRuntime?
    @Published var error = ""
    @Published var message = ""
    private let folder: URL
    private let dataFolder: URL
    private let trust: RuntimeTrust?
    private let session: URLSession
    private let extractArchive: @Sendable (URL, URL, RuntimePackage) throws -> Void
    private var task: Task<Void, Never>?
    private let downloader: RuntimeDownload

    convenience init(folder: URL? = nil) {
        self.init(
            runtimeFolder: folder ?? RuntimePaths.storage.appendingPathComponent("runtimes/mariadb"),
            dataFolder: RuntimePaths.storage.appendingPathComponent("database"), trust: RuntimeTrust.bundled,
            session: .shared, extractor: { image, destination, package in
                try Self.extract(image, destination: destination, package: package)
            })
    }
    private init(
        runtimeFolder: URL, dataFolder: URL, trust: RuntimeTrust?, session: URLSession,
        extractor: @escaping @Sendable (URL, URL, RuntimePackage) throws -> Void
    ) {
        folder = runtimeFolder
        self.dataFolder = dataFolder
        self.trust = trust
        self.session = session
        extractArchive = extractor
        downloader = RuntimeDownload(session: session)
        if trust?.teamID.isEmpty != false { availability = .unavailable }
        if Self.included {
            let version = RuntimePaths.version(of: "mariadb")
            availability = .unavailable
            installed = InstalledRuntime(
                id: "included", version: version,
                compatibilityLine: version.split(separator: ".").prefix(2).joined(separator: "."))
        } else if let data = try? Data(contentsOf: self.folder.appendingPathComponent("active.json")) {
            installed = try? JSONDecoder().decode(InstalledRuntime.self, from: data)
        }
        if !PreviewRuntime.isActive {
            let folder = self.folder
            Task.detached { Self.recoverStaging(in: folder) }
        }
    }
    #if DEBUG
        // Available only to the isolated development validation target. Production
        // always uses the bundled trust, Apple publisher checks and normal storage.
        convenience init(
            validationFolder: URL, databaseFolder: URL, trust: RuntimeTrust, session: URLSession,
            extractor: @escaping @Sendable (URL, URL, RuntimePackage) throws -> Void = { image, destination, package in
                try RuntimeComponents.extract(image, destination: destination, package: package)
            }
        ) {
            self.init(
                runtimeFolder: validationFolder, dataFolder: databaseFolder, trust: trust,
                session: session, extractor: extractor)
        }
    #endif
    func refresh() async {
        guard !PreviewRuntime.isActive, !busy else { return }
        guard let trust,
            trust.teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil
        else {
            availability = .unavailable
            error = ""
            return
        }
        busy = true
        phase = "checking available versions"
        error = ""
        let request = Task { await loadCatalog(trust) }
        task = request
        await request.value
    }
    private func loadCatalog(_ trust: RuntimeTrust) async {
        defer {
            busy = false
            phase = ""
            task = nil
        }
        do {
            async let catalogRequest = session.data(from: trust.catalogURL)
            async let signatureRequest = session.data(from: trust.signatureURL)
            let (catalog, signature) = try await (catalogRequest, signatureRequest)
            if (catalog.1 as? HTTPURLResponse)?.statusCode == 404
                || (signature.1 as? HTTPURLResponse)?.statusCode == 404 {
                availability = .unavailable
                return
            }
            guard (catalog.1 as? HTTPURLResponse)?.statusCode == 200,
                (signature.1 as? HTTPURLResponse)?.statusCode == 200
            else {
                throw DatabaseError.message(
                    "could not check available mariadb versions. try again")
            }
            packages = try trust.verify(catalog.0, signature: signature.0).packages
            availability = packages.isEmpty ? .unavailable : .available
        } catch {
            self.error = Task.isCancelled ? "version check cancelled" : error.localizedDescription
        }
    }
    func install(_ package: RuntimePackage, inactive: @escaping () -> Bool = { true }) {
        guard !busy, !PreviewRuntime.isActive else { return }
        guard packages.contains(package) else {
            error = "refresh and select a package from the verified catalog"
            return
        }
        guard inactive() else {
            error = "stop mariadb before installing or updating its component"
            return
        }
        if let installed, installed.compatibilityLine != package.compatibilityLine {
            error = "a major database upgrade requires a dedicated migration; your data was left unchanged"
            return
        }
        if let installed, package.version.compare(installed.version, options: .numeric) != .orderedDescending {
            error = "this version is already installed or is older. downgrades require a dedicated recovery"
            return
        }
        if installed == nil,
            FileManager.default.fileExists(
                atPath: dataFolder.appendingPathComponent("provisioned").path),
            package.compatibilityLine != "11.8" {
            error = "existing mariadb data requires the 11.8 compatibility line. migration is required for another line"
            return
        }
        busy = true
        phase = "preparing installation"
        task = Task { await performInstall(package, inactive: inactive) }
    }
    func cancel() {
        task?.cancel()
        downloader.cancel()
    }
    private func performInstall(_ package: RuntimePackage, inactive: () -> Bool) async {
        busy = true
        error = ""
        message = ""
        progress = 0
        phase = "downloading mariadb"
        let staging = folder.appendingPathComponent(".install-" + UUID().uuidString)
        defer {
            Self.cleanStaging(staging)
            busy = false
            phase = ""
            task = nil
        }
        do {
            try RuntimePaths.privateDirectory(staging)
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(
                to: staging.appendingPathComponent("owner.pid"), options: .atomic)
            try RuntimePaths.privateDirectory(dataFolder)
            let lease = try DatabaseRuntimeLease(directory: dataFolder)
            defer { withExtendedLifetime(lease) {} }
            guard DatabaseRuntimeLease.livePID(at: dataFolder.appendingPathComponent("server.pid")) == nil else {
                throw DatabaseError.message(
                    "another moko instance is using mariadb. stop that server before installing")
            }
            let disk = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard (disk.volumeAvailableCapacityForImportantUsage ?? 0) > package.bytes * 3 else {
                throw DatabaseError.message("not enough free space to install mariadb")
            }
            let file = staging.appendingPathComponent("runtime.dmg")
            try Task.checkCancellation()
            try await downloader.fetch(package.url, to: file) { fraction in
                Task { @MainActor in self.progress = fraction }
            }
            try Task.checkCancellation()
            phase = "verifying download"
            guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(package.bytes) else {
                throw DatabaseError.message("the download size does not match the signed catalog")
            }
            guard try RuntimeSignature.sha256(file) == package.sha256 else {
                throw DatabaseError.message("the download checksum does not match; the component was not installed")
            }
            phase = "validating publisher"
            let destination = staging.appendingPathComponent("payload")
            let extractor = extractArchive
            try await Task.detached {
                try extractor(file, destination, package)
            }.value
            try Task.checkCancellation()
            guard inactive() else {
                throw DatabaseError.message("mariadb started during installation. stop it and retry")
            }
            let target = folder.appendingPathComponent(package.id)
            var previous: URL?
            if FileManager.default.fileExists(atPath: target.path) {
                let backup = folder.appendingPathComponent("inactive-" + UUID().uuidString)
                try FileManager.default.moveItem(
                    at: target, to: backup)
                previous = backup
            }
            let active = InstalledRuntime(
                id: package.id, version: package.version, compatibilityLine: package.compatibilityLine,
                sourcesURL: package.sourcesURL, licensesURL: package.licensesURL)
            do {
                try FileManager.default.moveItem(at: destination, to: target)
                try JSONEncoder().encode(active).write(
                    to: folder.appendingPathComponent("active.json"), options: .atomic)
            } catch {
                try? FileManager.default.moveItem(at: target, to: destination)
                if let previous { try? FileManager.default.moveItem(at: previous, to: target) }
                throw error
            }
            installed = active
            message = "mariadb installed. start it when you are ready; your data was preserved"
        } catch {
            self.error =
                Task.isCancelled || (error as NSError).code == NSURLErrorCancelled
                ? "installation cancelled" : error.localizedDescription
        }
    }
    nonisolated private static func recoverStaging(in folder: URL) {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(".install-") {
            guard DatabaseRuntimeLease.livePID(at: entry.appendingPathComponent("owner.pid")) == nil,
                entry.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/"),
                let created = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate,
                Date().timeIntervalSince(created) > 60
            else { continue }
            cleanStaging(entry)
        }
    }
    nonisolated private static func isMounted(_ mount: URL) -> Bool {
        let info = execute("/usr/bin/hdiutil", ["info", "-plist"])
        guard info.code == 0, let data = info.output.data(using: .utf8),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let images = plist["images"] as? [[String: Any]]
        else { return true }
        return images.contains { image in
            (image["system-entities"] as? [[String: Any]])?.contains { $0["mount-point"] as? String == mount.path }
                == true
        }
    }
    nonisolated private static func cleanStaging(_ staging: URL) {
        let mount = staging.appendingPathComponent("mounted")
        if FileManager.default.fileExists(atPath: mount.path) && isMounted(mount) {
            guard execute("/usr/bin/hdiutil", ["detach", mount.path]).code == 0 else { return }
        }
        try? FileManager.default.removeItem(at: staging)
    }
    nonisolated private static func extract(_ image: URL, destination: URL, package: RuntimePackage) throws {
        let assessment = execute(
            "/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", image.path])
        guard assessment.code == 0 else {
            throw DatabaseError.message("the runtime package has not passed Apple notarization")
        }
        try RuntimeArchive.copyVerified(image, destination: destination, package: package) { runtime in
            try RuntimeSignature.validate(runtime, teamID: package.teamID)
        }
    }
    func remove() throws {
        guard !busy, let installed else { return }
        guard !Self.included else { throw DatabaseError.message("mariadb is part of this moko version") }
        try RuntimePaths.privateDirectory(dataFolder)
        let lease = try DatabaseRuntimeLease(directory: dataFolder)
        defer { withExtendedLifetime(lease) {} }
        guard DatabaseRuntimeLease.livePID(at: dataFolder.appendingPathComponent("server.pid")) == nil else {
            throw DatabaseError.message("stop mariadb before removing its component")
        }
        let target = folder.appendingPathComponent(installed.id).resolvingSymlinksInPath()
        guard target.path.hasPrefix(folder.resolvingSymlinksInPath().path + "/") else {
            throw DatabaseError.message("the component location is invalid")
        }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("active.json"))
        // Keep previous binaries recoverable, separately from database data.
        try? FileManager.default.moveItem(at: target, to: folder.appendingPathComponent("removed-" + UUID().uuidString))
        self.installed = nil
        message = "mariadb removed. its database files were preserved"
    }
    #if DEBUG
        static func preview(_ state: String) -> RuntimeComponents {
            let model = RuntimeComponents(
                folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            model.availability = .available
            model.packages = [
                .init(
                    id: "mariadb-11.8.9-arm64", engine: "mariadb", version: "11.8.9",
                    compatibilityLine: "11.8", architecture: "arm64", minimumOS: "26.0", bytes: 150_000_000,
                    sha256: String(repeating: "a", count: 64), url: URL(string: "https://example.invalid/runtime.dmg")!,
                    sourcesURL: URL(string: "https://example.invalid/source.zip")!,
                    licensesURL: URL(string: "https://example.invalid/license")!,
                    teamID: "ABCDE12345"),
            ]
            switch state {
            case "unavailable":
                model.availability = .unavailable
                model.packages = []
            case "download":
                model.busy = true
                model.phase = "downloading mariadb"
                model.progress = 0.42
            case "verifying":
                model.busy = true
                model.phase = "validating publisher"
                model.progress = 1
            case "error": model.error = "the download checksum does not match; the component was not installed"
            case "cancelled": model.error = "installation cancelled"
            case "installed":
                model.installed = .init(id: "mariadb-11.8.9-arm64", version: "11.8.9", compatibilityLine: "11.8")
            default: break
            }
            return model
        }
    #endif
}

enum RuntimeArchive {
    static func copyVerified(
        _ image: URL, destination: URL, package: RuntimePackage, validate: (URL) throws -> Void
    ) throws {
        let mount = image.deletingLastPathComponent().appendingPathComponent("mounted")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
        let attached = execute(
            "/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, image.path])
        guard attached.code == 0 else { throw DatabaseError.message("could not open the component package") }
        var mounted = true
        defer { if mounted { _ = execute("/usr/bin/hdiutil", ["detach", mount.path]) } }
        let runtime = mount.appendingPathComponent("MariaDB.runtime")
        try validate(runtime)
        let info =
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: runtime.appendingPathComponent("Contents/Info.plist")), format: nil)
            as? [String: Any]
        let inventory =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: runtime.appendingPathComponent("Contents/Resources/Runtime/Manifest.json")))
            as? [String: [String: Any]]
        guard info?["CFBundlePackageType"] as? String == "BNDL",
            info?["CFBundleShortVersionString"] as? String == package.version,
            inventory?["mariadb@11.8"]?["version"] as? String == package.version
        else { throw DatabaseError.message("the runtime version does not match the signed catalog") }
        guard
            ["mariadbd", "mariadb", "mariadb-dump", "mariadb-install-db"].allSatisfy({
                FileManager.default.isExecutableFile(
                    atPath: runtime.appendingPathComponent("Contents/Resources/Runtime/MariaDB/bin/" + $0).path)
            })
        else {
            throw DatabaseError.message("the component package does not contain mariadb")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: runtime, to: destination.appendingPathComponent("MariaDB.runtime"))
        guard execute("/usr/bin/hdiutil", ["detach", mount.path]).code == 0 else {
            throw DatabaseError.message("close files opened from the component package and retry installation")
        }
        mounted = false
    }
}
