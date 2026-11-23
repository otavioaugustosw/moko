import AppKit
import Security
import SwiftUI

@available(macOS 26.0, *)
final class MokoWindow: NSWindow {
    var minimizeToMenuBar: (() -> Void)?
    override func miniaturize(_ sender: Any?) {
        if let minimizeToMenuBar { minimizeToMenuBar() } else { super.miniaturize(sender) }
    }
}
@available(macOS 26.0, *)
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = WorkspaceModel()
    var window: NSWindow!
    var item: NSStatusItem!
    private var menuIcon: NSImage?
    private var wantsPanelVisible = true
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewRuntime.isActive else { return }
        // SQL typed in any editor must keep straight quotes and double hyphens.
        UserDefaults.standard.register(defaults: [
            "NSAutomaticQuoteSubstitutionEnabled": false, "NSAutomaticDashSubstitutionEnabled": false
        ])
        let appMenu = NSMenu()
        let appEntry = NSMenuItem()
        let commands = NSMenu()
        let close = NSMenuItem(title: "close window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        commands.addItem(close)
        commands.addItem(withTitle: "quit moko", action: #selector(quit), keyEquivalent: "q").target = self
        appEntry.submenu = commands
        appMenu.addItem(appEntry)
        NSApp.mainMenu = appMenu
        let editEntry = NSMenuItem()
        let editMenu = NSMenu(title: "edit")
        for (title, action, key) in [
            ("undo", Selector(("undo:")), "z"), ("cut", #selector(NSText.cut(_:)), "x"),
            ("copy", #selector(NSText.copy(_:)), "c"), ("paste", #selector(NSText.paste(_:)), "v"),
            ("select all", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editEntry.submenu = editMenu
        appMenu.addItem(editEntry)
        let windowEntry = NSMenuItem()
        let windowMenu = NSMenu(title: "window")
        windowMenu.addItem(withTitle: "minimize to menu bar", action: #selector(minimizeToMenuBar), keyEquivalent: "m")
            .target = self
        windowEntry.submenu = windowMenu
        appMenu.addItem(windowEntry)
        window = MokoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 670),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        (window as? MokoWindow)?.minimizeToMenuBar = { [weak self] in self?.minimizeToMenuBar() }
        window.title = "moko"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 900, height: 640)
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        model.begin()
        window.contentView = NSHostingView(rootView: Dashboard(model: model))
        window.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        if let image = NSImage(named: "MenuIcon") {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = true
            menuIcon = image
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        model.notify = { [weak self] in self?.updateItem() }
        updateItem()
        show()
    }
    @objc func show() {
        guard !PreviewRuntime.isActive, let window else { return }
        wantsPanelVisible = true
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        model.databaseBrowser.setWindowVisible(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // AppKit applies activation-policy and miniaturization changes asynchronously.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsPanelVisible else { return }
            if self.window.isMiniaturized { self.window.deminiaturize(nil) }
            self.window.makeKeyAndOrderFront(nil)
            self.window.orderFrontRegardless()
        }
    }
    @objc func minimizeToMenuBar() {
        wantsPanelVisible = false
        model.databaseBrowser.setWindowVisible(false)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
    func windowDidMiniaturize(_ notification: Notification) {
        if wantsPanelVisible { minimizeToMenuBar() }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if wantsPanelVisible { model.databaseBrowser.setWindowVisible(true) }
    }
    func windowWillClose(_ notification: Notification) {
        wantsPanelVisible = false
        model.databaseBrowser.setWindowVisible(false)
        let keep = UserDefaults.standard.object(forKey: "moko.keepInDockOnClose") as? Bool ?? true
        NSApp.setActivationPolicy(keep ? .regular : .accessory)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !PreviewRuntime.isActive else { return .terminateNow }
        model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    @objc func quit() {
        if let window, let sheet = window.attachedSheet { window.endSheet(sheet) }
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !PreviewRuntime.isActive else { return false }
        show()
        return true
    }
    @objc func start() { model.control("start") }
    @objc func stop() { model.control("stop") }
    @objc func restart() { model.control("restart") }
    @objc func refresh() { model.refresh(manual: true) }
    @objc func connection() {
        model.page = "settings"
        model.settingsSection = "connection"
        show()
    }
    @objc func account() {
        model.page = "settings"
        model.settingsSection = "account"
        show()
    }
    @objc func copyData() { model.copyConnection() }
    @objc func sessions() {
        model.showSessions()
        show()
    }
    @objc func settings() {
        model.page = "settings"
        model.settingsSection = "application"
        show()
    }
    func updateItem() {
        item.button?.toolTip = model.displayStatus + " · " + (model.actualPort == "—" ? model.port : model.actualPort)
        item.button?.setAccessibilityLabel("moko — " + model.displayStatus)
    }
    @objc func serviceCommand(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let pieces = value.split(separator: ":")
        guard pieces.count == 2, let engine = DatabaseEngine(rawValue: String(pieces[0])) else { return }
        model.controlService(engine, command: String(pieces[1]))
    }
    @objc func togglePHP() {
        if model.phpServer.running {
            model.phpServer.stop()
        } else if model.phpServer.projects.active == nil {
            model.page = "web server"
            show()
        } else {
            model.phpServer.start(connection: model.phpConnection())
        }
    }
    @objc func components() { model.page = "settings"; model.settingsSection = "components"; show() }
    @objc func existingServiceCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        model.control(command)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ selector: Selector?, enabled: Bool = true) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        add(model.displayStatus, nil, enabled: false)
        add(
            "port \(model.actualPort == "—" ? model.port + " (configured)" : model.actualPort) · \(model.username)",
            nil, enabled: false)
        menu.addItem(.separator())
        add("open panel", #selector(show))
        add("connections…", #selector(sessions))
        for engine in [DatabaseEngine.postgresql, .mariadb] {
            if engine == .mariadb && RuntimePaths.installedMariaDB == nil { continue }
            let running = engine.isPostgreSQL ? model.postgresql.running : model.managedDatabase.running
            let busy = engine.isPostgreSQL ? model.postgresql.busy : model.managedDatabase.busy
            let submenu = NSMenu(title: engine.rawValue)
            let parent = NSMenuItem(title: engine.rawValue + " · " + (running ? "running" : "stopped"), action: nil, keyEquivalent: "")
            for command in (running ? ["stop", "restart"] : ["start"]) {
                let item = NSMenuItem(title: command + " " + engine.rawValue, action: #selector(serviceCommand(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = engine.rawValue + ":" + command
                item.isEnabled = !busy
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        if model.controlsExistingMySQL {
            let parent = NSMenuItem(title: "existing mysql · " + model.host + ":" + model.port, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "existing mysql")
            for command in (model.running ? ["stop", "restart"] : ["start"]) {
                let entry = NSMenuItem(title: command + " existing mysql", action: #selector(existingServiceCommand(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = command
                entry.isEnabled = !model.working
                submenu.addItem(entry)
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        if RuntimePaths.installedMariaDB == nil { add("install mariadb…", #selector(components)) }
        add(model.phpServer.running ? "stop php" : "start php", #selector(togglePHP), enabled: !model.phpServer.busy)
        menu.addItem(.separator())
        add("copy connection details", #selector(copyData))
        menu.addItem(.separator())
        add("quit moko", #selector(quit))
    }
}
func modelColor(_ state: LightState) -> NSColor { state.color }
@main
struct Entry {
    static func main() {
        guard #available(macOS 26.0, *) else { return }
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains("--mcp") { AgentServer.run() }
        runRuntimeCheckIfRequested()
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--ui-fixture" {
            let model = WorkspaceModel()
            model.configureBackend(allowCredentialInteraction: false)
            guard let secret = Credentials.read(model.diagnosticCredentialAccount, allowInteraction: false) else {
                print("credential unavailable")
                exit(1)
            }
            let connection = DatabaseConnection(
                host: model.host, port: model.port, user: model.username, password: secret)
            let success = InterfaceFixture.run(
                connection, mode: CommandLine.arguments[2], stateURL: URL(fileURLWithPath: CommandLine.arguments[3]))
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--check-databases") || CommandLine.arguments.contains("--test-databases") {
            let model = WorkspaceModel()
            model.configureBackend(allowCredentialInteraction: false)
            guard let secret = Credentials.read(model.diagnosticCredentialAccount, allowInteraction: false) else {
                print("credential unavailable")
                exit(1)
            }
            let connection = DatabaseConnection(
                host: model.host, port: model.port, user: model.username, password: secret)
            let success =
                CommandLine.arguments.contains("--test-databases")
                ? DatabaseChecks.validate(connection) : DatabaseChecks.inspect(connection)
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--check-sessions") || CommandLine.arguments.contains("--hold-check-session") {
            let model = WorkspaceModel()
            model.configureBackend(allowCredentialInteraction: false)
            guard let secret = Credentials.read(model.diagnosticCredentialAccount, allowInteraction: false) else {
                print("credential unavailable")
                exit(1)
            }
            if CommandLine.arguments.contains("--hold-check-session") {
                for _ in 0..<15 {
                    let result = model.query(
                        "SELECT SLEEP(2);", password: secret, host: model.host, port: model.port, user: model.username)
                    guard result.code == 0 else {
                        print("test session interrupted. code \(result.code).")
                        exit(1)
                    }
                }
                print("temporary test session ended.")
                exit(0)
            }
            let result = model.query(
                WorkspaceModel.sessionSQL, password: secret, host: model.host, port: model.port, user: model.username)
            guard result.code == 0 else {
                print("session query did not complete. code \(result.code).")
                exit(1)
            }
            do {
                let sessions = try ServerSession.decode(result.output)
                print("sessions read: \(sessions.count).")
            } catch {
                print("invalid session format.")
                exit(1)
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--check-keychain") {
            let model = WorkspaceModel()
            model.configureBackend(allowCredentialInteraction: false)
            let saved = Credentials.load(allowInteraction: false)
            let status = saved.passwords[model.diagnosticCredentialAccount] == nil && saved.status == errSecSuccess
                ? errSecItemNotFound : saved.status
            print(
                status == errSecSuccess
                    ? "keychain: access granted without a dialog." : "keychain: access not confirmed. code \(status).")
            exit(status == errSecSuccess ? 0 : 1)
        }
        if CommandLine.arguments.contains("--import-credentials") {
            // Standard input: one "account<TAB>password" per line. Nothing is echoed.
            var entries = [String: String]()
            while let line = readLine() {
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2, !parts[0].isEmpty { entries[String(parts[0])] = String(parts[1]) }
            }
            let success = !entries.isEmpty && Credentials.save(entries)
            print(success ? "keychain: \(entries.count) credentials saved." : "could not save the credentials.")
            exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--diagnose") {
            let model = WorkspaceModel()
            model.configureBackend(allowCredentialInteraction: false)
            guard let secret = Credentials.read(model.diagnosticCredentialAccount, allowInteraction: false) else {
                print("credential unavailable")
                exit(1)
            }
            let result = model.query(
                "SELECT @@port, @@version, CURRENT_USER(), @@hostname, @@socket;", password: secret, host: model.host,
                port: model.port, user: model.username, localSocket: CommandLine.arguments.contains("--socket"))
            print(result.code == 0 ? result.output : "connection failed. code: \(result.code)")
            exit(result.code == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--control") {
            print("external servers are connection-only. use moko's independent local service controls.")
            exit(2)
        }
        let app = NSApplication.shared
        let delegate = ApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    @available(macOS 26.0, *)
    private static func runRuntimeCheckIfRequested() {
        let checks: [(argument: String, run: () -> Bool)] = [
            ("--test-postgresql-runtime", PostgreSQLRuntimeChecks.run),
            ("--test-database-export", DatabaseExportChecks.run),
            ("--test-sql-objects", DatabaseObjectRuntimeChecks.run),
            ("--test-managed-database", ManagedDatabaseRuntimeChecks.run),
            ("--test-php-projects", PHPProjectRuntimeChecks.run),
            ("--test-table-creation", DatabaseChecks.runTableCreationCheck),
        ]
        for check in checks where CommandLine.arguments.contains(where: { $0.hasPrefix(check.argument) }) {
            exit(check.run() ? 0 : 1)
        }
    }
}
