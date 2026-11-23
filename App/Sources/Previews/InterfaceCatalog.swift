#if DEBUG
    import SwiftUI

    struct InterfaceScenario: Identifiable {
        let id: String
        let components: [String]
    }

    @MainActor @available(macOS 26.0, *)
    enum InterfaceCatalog {
        static let sharedComponents = [
            "Dashboard", "MokoContextSidebar", "WindowSidebarMaterial", "Surface", "DetailRow", "MokoButtonStyle",
            "ConnectionProfilePicker", "TransientNotice", "PHPProjectPresentation",
        ]
        static var scenarios: [InterfaceScenario] {
            var values: [InterfaceScenario] = [
                .init(
                    id: "screen.overview",
                    components: sharedComponents + [
                        "LocalDatabaseOverview", "ServerOverview", "PHPOverview", "TrafficLight", "ServiceSummary",
                        "OptionalMariaDBCard",
                    ]),
                .init(id: "screen.connections", components: sharedComponents),
                .init(id: "screen.external", components: sharedComponents + ["DatabaseServerDetails"]),
                .init(id: "screen.activity", components: sharedComponents),
                .init(
                    id: "screen.web server",
                    components: sharedComponents + [
                        "WebServerView", "PHPWorkspace", "PHPProjectSidebar", "PHPDatabaseConfiguration",
                    ]),
                .init(id: "screen.support", components: sharedComponents + ["SupportView", "CreatorProfile"]),
                .init(
                    id: "screen.databases",
                    components: sharedComponents + [
                        "DatabaseWorkspace", "DatabaseNavigator", "DatabaseObjectNavigator", "SQLGrid", "RefreshClock",
                        "DatabaseServerDetails",
                    ]),
                .init(id: "screen.structure", components: sharedComponents + ["PostgreSQLStructureObjects"]),
                .init(id: "screen.sql", components: sharedComponents + ["SQLBodyEditor"]),
                .init(id: "legal", components: ["LegalDocumentsView", "LegalDocumentText"]),
                .init(id: "table.mariadb", components: ["NewTableView"]),
                .init(id: "table.postgresql", components: ["NewTableView"]),
                .init(id: "row.new", components: ["RowEditor", "SQLValueField"]),
                .init(id: "row.edit", components: ["RowEditor", "SQLValueField"]),
                .init(id: "column.mariadb", components: ["ColumnEditor"]),
                .init(id: "column.postgresql", components: ["PostgreSQLColumnEditor"]),
                .init(id: "delete", components: ["DestructiveReview"]),
                .init(id: "delete.sheet", components: ["DestructiveReview"]),
                .init(id: "confirmation", components: ["DatabaseConfirmation"]),
                .init(id: "profile", components: ["ConnectionProfileEditor"]),
                .init(id: "foreign-key", components: ["ForeignKeyPreview"]),
                .init(
                    id: "widgets",
                    components: [
                        "SQLValueField", "NativeSQLDatePicker", "SQLBodyEditor", "RoutineTypePicker", "RefreshClock",
                        "AppearancePicker", "TrafficLight", "Surface", "DetailRow", "MokoButtonStyle",
                    ]),
                .init(id: "notice", components: ["TransientNotice"]),
                .init(id: "object.workspace", components: ["DatabaseObjectWorkspace", "SQLBodyEditor"]),
            ]
            for section in ["connection", "account", "application", "components"] {
                values.append(
                    .init(
                        id: "settings." + section,
                        components: sharedComponents + [
                            "ConnectionProfileSettings", "AppearancePicker", "ComponentsView",
                        ]))
            }
            for step in 0...6 {
                values.append(
                    .init(
                        id: "onboarding.\(step)",
                        components: [
                            "OnboardingView", "OnboardingWelcome", "OnboardingFeatures", "OnboardingSetup",
                            "OnboardingPHPSetup", "AgentAccessPanel",
                            "OnboardingForm", "OnboardingField", "SQLSetupSelector", "SQLSetupOption",
                            "SQLSetupOptionStyle",
                        ]))
            }
            for state in ["unavailable", "ready", "download", "verifying", "cancelled", "error", "installed"] {
                values.append(.init(id: "runtime." + state, components: ["ComponentsView", "MariaDBInstallation"]))
            }
            for state in ["testing", "starting", "stopped", "success", "failure"] {
                values.append(.init(id: "connection." + state, components: ["ConnectionTestPopup"]))
            }
            for kind in PostgreSQLConstraintDraft.Kind.allCases {
                values.append(
                    .init(id: "constraint." + kind.rawValue, components: ["PostgreSQLConstraintEditor", "ObjectField"]))
            }
            values.append(
                .init(id: "mariadbconstraint.foreign key", components: ["PostgreSQLConstraintEditor", "ObjectField"]))
            for kind in ["switch", "missing", "remove", "update"] {
                values.append(.init(id: "project." + kind, components: ["PHPProjectDialog"]))
            }
            for kind in DatabaseObjectKind.allCases {
                values.append(
                    .init(
                        id: "object." + kind.rawValue,
                        components: [
                            "NewDatabaseObjectView", "ObjectParameterFields", "ObjectField", "RoutineTypePicker",
                            "SQLBodyEditor",
                        ]))
            }
            for kind in ["date", "time", "datetime"] {
                values.append(.init(id: "temporal." + kind, components: ["SQLTemporalEditor", "NativeSQLDatePicker"]))
            }
            return values
        }
        static func objectDefinition(engine: DatabaseEngine = .mariadb) -> DatabaseObjectDefinition {
            .init(
                object: .init(name: "count_items", kind: .procedure, detail: "", enabled: true),
                sql: "CREATE PROCEDURE count_items(IN minimum int) BEGIN SELECT minimum; END",
                body: "BEGIN SELECT minimum; END", sqlMode: "STRICT_TRANS_TABLES", collation: "utf8mb4_unicode_ci",
                parameters: [.init(ordinal: 1, name: "minimum", mode: "IN", type: "int")], engine: engine)
        }
    }

    @MainActor @available(macOS 26.0, *)
    struct MokoComponentFixture: View {
        let scenario: String
        @StateObject private var server: WorkspaceModel
        @StateObject private var browser: DatabaseModel
        @State private var value = "2026-10-13"
        @State private var date = Date(timeIntervalSince1970: 1_792_000_000)
        @State private var selectedAppearance = "system"
        @State private var notice = "changes applied"
        @State private var result = ""
        @State private var showingDeletion = false
        init(scenario: String) {
            self.scenario = scenario
            let model = PreviewFixtures.server()
            if scenario.hasPrefix("settings.") {
                model.page = "settings"
                model.settingsSection = String(scenario.dropFirst(9))
            } else if scenario.hasPrefix("screen.") {
                let page = String(scenario.dropFirst(7))
                model.page = ["structure", "sql"].contains(page) ? "databases" : page
                if ["structure", "sql"].contains(page) { model.databaseBrowser.tab = page }
                if page == "external" {
                    let id = UUID()
                    let profile = ConnectionProfile(
                        id: id, name: "existing server", engine: .mysql, managed: false,
                        host: "127.0.0.1", port: "3306", user: "fixture", database: "shop", tlsMode: "prefer",
                        rootCertificate: "", credentialAccount: "ui-fixture-only")
                    model.profiles.save(profile)
                    model.selectProfile(id)
                    model.page = "overview"
                }
            }
            model.databaseBrowser.connection = model.currentConnection
            model.databaseBrowser.schemas = ["public", "shop"]
            model.databaseBrowser.schema = "shop"
            let project = model.phpServer.projects.add(RuntimePaths.storage.appendingPathComponent("shop"))
            model.phpServer.projects.activate(project)
            model.phpServer.projects.associate(project, profileID: model.profiles.selectedID, database: "shop")
            model.phpServer.documentRoot = project.path
            model.events = [Event(text: "server started"), Event(text: "connection tested")]
            _server = StateObject(wrappedValue: model)
            _browser = StateObject(
                wrappedValue: PreviewFixtures.browser(
                    engine: scenario == "table.mariadb" || scenario.hasPrefix("mariadbconstraint.")
                        ? .mariadb : .postgresql))
        }
        var body: some View {
            content.buttonStyle(MokoButtonStyle()).tint(MokoTheme.selectionInk).foregroundStyle(MokoTheme.ink)
                .background(MokoTheme.canvas)
                .defaultAppStorage(PreviewFixtures.preferences)
                .overlay(alignment: .bottomTrailing) { Text(result).accessibilityIdentifier("fixture-result") }
        }
        @ViewBuilder private var content: some View {
            if scenario.hasPrefix("screen.") || scenario.hasPrefix("settings.") {
                Dashboard(model: server)
            } else if scenario.hasPrefix("onboarding.") {
                OnboardingView(server: server, initialStep: Int(scenario.split(separator: ".").last ?? "0") ?? 0) {
                    result = "onboarding completed"
                }
            } else if scenario.hasPrefix("runtime.") {
                ComponentsView(server: server, components: RuntimeComponents.preview(String(scenario.dropFirst(8))))
                    .padding(24).frame(maxWidth: 720)
            } else if scenario.hasPrefix("connection.") {
                ConnectionTestPopup(model: server, initial: connectionTest)
            } else if scenario.hasPrefix("constraint.") {
                PostgreSQLConstraintEditor(
                    browser: browser,
                    draft: .init(
                        kind: PostgreSQLConstraintDraft.Kind(rawValue: String(scenario.dropFirst(11))) ?? .index))
            } else if scenario.hasPrefix("mariadbconstraint.") {
                PostgreSQLConstraintEditor(browser: browser, draft: .init(kind: .foreignKey))
            } else if scenario.hasPrefix("project.") {
                PHPProjectDialog(php: server.phpServer, prompt: projectPrompt)
            } else if scenario.hasPrefix("object."), scenario != "object.workspace" {
                NewDatabaseObjectView(
                    library: objectLibrary, tables: browser.tables,
                    draft: .init(kind: DatabaseObjectKind(rawValue: String(scenario.dropFirst(7))) ?? .procedure),
                    close: {})
            } else if scenario.hasPrefix("temporal.") {
                SQLTemporalEditor(
                    name: "value", kind: temporalKind, value: temporalValue,
                    save: { text, done in
                        result = text
                        done(nil)
                    }, close: { if result.isEmpty { result = "closed" } })
            } else {
                individual
            }
        }
        @ViewBuilder private var individual: some View {
            switch scenario {
            case "legal": LegalDocumentsView()
            case "table.mariadb", "table.postgresql": NewTableView(browser: browser)
            case "row.new", "row.edit":
                RowEditor(
                    browser: browser, columns: PreviewFixtures.columns,
                    draft: PreviewFixtures.row(editing: scenario == "row.edit"), submit: { _ in result = "submitted" })
            case "column.mariadb":
                ColumnEditor(
                    browser: browser, draft: .init(original: "nome", name: "nome", definition: "varchar(80) NOT NULL"),
                    submit: { _ in result = "submitted" })
            case "column.postgresql":
                PostgreSQLColumnEditor(
                    browser: browser,
                    draft: .init(
                        column: .init(
                            name: "price", type: "numeric(12,2)",
                            nullable: false, key: "", defaultValue: "0", extra: "", collation: "", comment: "",
                            engine: .postgresql)))
            case "delete":
                DestructiveReview(
                    title: "delete row", message: "this removes one row from shop.items.", actionTitle: "delete",
                    cancel: { result = "cancelled" }, confirm: { result = "deleted" })
            case "delete.sheet":
                Button("review deletion") { showingDeletion = true }
                    .sheet(isPresented: $showingDeletion) {
                        DestructiveReview(
                            title: "delete row", message: "this removes one row from shop.items.", actionTitle: "delete",
                            cancel: { result = "cancelled"; showingDeletion = false },
                            confirm: { result = "deleted"; showingDeletion = false })
                    }
            case "confirmation":
                DatabaseConfirmation(
                    plan: .init(
                        title: "delete table", sql: "DROP TABLE shop.items", database: "shop", destructive: true),
                    browser: browser, close: { result = "closed" })
            case "profile": ConnectionProfileEditor(server: server, profile: externalProfile)
            case "foreign-key":
                ForeignKeyPreview(
                    target: .init(
                        constraint: "fk_category", database: "shop", table: "categories",
                        predicate: "id = 1", summary: "id = 1"), connection: server.currentConnection,
                    initialResponse: .init(results: [PreviewFixtures.result], code: 0, error: "", rolledBack: false),
                    open: {})
            case "notice":
                VStack {
                    Button("show message") { notice = "changes applied" }
                    TransientNotice($notice)
                }.padding(24)
            case "object.workspace": DatabaseObjectWorkspace(library: objectLibrary).padding(24)
            case "widgets": widgets
            default: Text("unregistered fixture")
            }
        }
        private var widgets: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TrafficLight(state: .red)
                    TrafficLight(state: .yellow)
                    TrafficLight(state: .green)
                }
                SQLValueField(column: PreviewFixtures.columns[2], text: $value)
                NativeSQLDatePicker(kind: .date, value: $date).frame(width: 190, height: 170)
                RoutineTypePicker(type: $value)
                RefreshClock(browser: browser)
                AppearancePicker(selection: $selectedAppearance)
                HStack {
                    Button("normal") {}.buttonStyle(MokoButtonStyle())
                    Button("primary") {}.buttonStyle(MokoButtonStyle(prominent: true))
                    Button("disabled") {}.buttonStyle(MokoButtonStyle(prominent: true, inverted: true)).disabled(true)
                    Button("delete", role: .destructive) {}.buttonStyle(MokoButtonStyle())
                }
                Surface { DetailRow(name: "address", value: "127.0.0.1:15432") }
            }.padding(24).frame(maxWidth: 720)
        }
        private var objectLibrary: DatabaseObjectLibrary {
            .preview(
                definition: InterfaceCatalog.objectDefinition(
                    engine: ["object.schema", "object.sequence", "object.materialized view"].contains(scenario)
                        ? .postgresql : .mariadb))
        }
        private var externalProfile: ConnectionProfile {
            .init(
                id: UUID(), name: "test connection", engine: .postgresql, managed: false, host: "127.0.0.1",
                port: "5432", user: "fixture", database: "postgres", tlsMode: "prefer", rootCertificate: "",
                credentialAccount: "ui-fixture-only")
        }
        private var connectionTest: ConnectionTest {
            let phase: ConnectionTest.Phase
            switch scenario {
            case "connection.testing": phase = .testing
            case "connection.starting": phase = .starting
            case "connection.stopped": phase = .serverStopped
            case "connection.success": phase = .success
            default: phase = .failure(1045, "access denied for fixture user")
            }
            return .init(host: "127.0.0.1", port: "15432", user: "fixture", phase: phase)
        }
        private var projectPrompt: PHPProjectPrompt {
            let kind: PHPProjectPrompt.Kind
            switch scenario {
            case "project.switch": kind = .switchProject
            case "project.missing": kind = .missingFolder
            case "project.remove": kind = .removeProject
            default: kind = .updateFolder
            }
            return .init(
                project: PHPProject(path: RuntimePaths.storage.appendingPathComponent("shop").path), kind: kind)
        }
        private var temporalKind: SQLTemporalKind {
            scenario == "temporal.date" ? .date : (scenario == "temporal.time" ? .time : .datetime)
        }
        private var temporalValue: String {
            scenario == "temporal.date"
                ? "2026-10-13" : (scenario == "temporal.time" ? "19:30:00" : "2026-10-13 19:30:00")
        }
    }
#endif
