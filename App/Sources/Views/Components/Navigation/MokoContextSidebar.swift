import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct MokoContextSidebar: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var browser: DatabaseModel
    @ObservedObject var filters: PanelFilters
    var title: String {
        switch model.page {
        case "databases": "databases"
        case "connections": "connections"
        case "activity": "history"
        case "settings": "preferences"
        case "web server": "php"
        case "support": "support"
        default: "server"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline).padding(.horizontal, 12).padding(.top, 24)
            if model.page == "databases" {
                ConnectionProfilePicker(server: model, profiles: model.profiles).padding(.horizontal, 12)
                DatabaseNavigator(browser: browser).padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.page {
                        case "connections": sessionsSidebar
                        case "activity": activitySidebar
                        case "settings": settingsSidebar
                        case "web server": webSidebar
                        case "support": supportSidebar
                        default: serverSidebar
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }.scrollIndicators(.visible).frame(
                    maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Text("moko").font(.system(size: 40, weight: .regular, design: .serif)).tracking(-1.5)
                .foregroundStyle(MokoTheme.wordmark).padding(.horizontal, 16).padding(.bottom, 16).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MokoTheme.sidebar)
    }

    func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(MokoTheme.secondaryInk).padding(.bottom, 2)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func action(
        _ title: String, icon: String, subtitle: String? = nil, count: Int? = nil,
        selected: Bool = false, enabled: Bool = true, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon).font(
                    .system(size: 15, weight: selected ? .semibold : .regular)
                ).frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(MokoTheme.secondaryInk).lineLimit(1)
                            .help(subtitle)
                    }
                }
                Spacer(minLength: 2)
                if let count {
                    Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(MokoTheme.secondaryInk)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(
                Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? MokoTheme.selectionInk : MokoTheme.ink)
            .disabled(!enabled).opacity(enabled ? 1 : 0.45).accessibilityLabel(title)
    }
    var endpoint: String {
        "\(model.host):\(model.actualPort == "—" ? model.port : model.actualPort)"
    }
    func openSettings(_ section: String) {
        model.settingsSection = section
        model.page = "settings"
        model.notice = ""
    }
    var serverSidebar: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(
                        Color(nsColor: (model.working ? LightState.yellow : model.light).color)
                    ).frame(width: 7, height: 7)
                    Text(model.displayStatus).font(.system(size: 12, weight: .medium))
                }
                Text(endpoint).font(.callout).textSelection(.enabled)
            }
            group("connection") {
                action("refresh status", icon: "arrow.clockwise", enabled: !model.working) {
                    model.refresh(manual: true)
                }
                action("test connection", icon: "network", enabled: !model.working) {
                    model.testConnection()
                }
                action("copy connection", icon: "doc.on.doc", perform: model.copyConnection)
            }
            group("configuration") {
                action("connection", icon: "slider.horizontal.3") { openSettings("connection") }

            }
        }
    }
    var sessionDatabases: [String] {
        var values = Set(model.sessions.map(\.database))
        if let selected = filters.sessionDatabase { values.insert(selected) }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var sessionsSidebar: some View {
        Group {
            ConnectionProfilePicker(server: model, profiles: model.profiles)
            TextField("search sessions", text: $filters.sessionQuery).textFieldStyle(.roundedBorder)
                .help("search by user, host, database, state or id")
            group("state") {
                ForEach(SessionScope.allCases, id: \.self) { scope in
                    action(
                        scope.title, icon: scope.icon,
                        count: model.sessions.filter(scope.includes).count,
                        selected: filters.sessionScope == scope
                    ) { filters.sessionScope = scope }
                }
            }
            group("database") {
                action(
                    "all databases", icon: "square.stack.3d.up", count: model.sessions.count,
                    selected: filters.sessionDatabase == nil
                ) { filters.sessionDatabase = nil }
                ForEach(sessionDatabases, id: \.self) { database in
                    action(
                        database.isEmpty ? "no database" : database, icon: "externaldrive",
                        count: model.sessions.filter { $0.database == database }.count,
                        selected: filters.sessionDatabase == database
                    ) { filters.sessionDatabase = database }
                }
            }
            group("actions") {
                action("refresh sessions", icon: "arrow.clockwise", enabled: !model.working) {
                    model.refresh(manual: true)
                }
                action(
                    "clear filters", icon: "line.3.horizontal.decrease",
                    enabled: filters.hasSessionFilters, perform: filters.clearSessions)
            }
        }
    }
    var activitySidebar: some View {
        Group {
            TextField("search events", text: $filters.activityQuery).textFieldStyle(
                .roundedBorder)
            group("show") {
                ForEach(ActivityLimit.allCases, id: \.self) { limit in
                    action(
                        limit.title, icon: limit == .all ? "list.bullet" : "clock",
                        selected: filters.activityLimit == limit
                    ) { filters.activityLimit = limit }
                }
            }
            group("order") {
                action("newest first", icon: "arrow.down", selected: !filters.oldestFirst) {
                    filters.oldestFirst = false
                }
                action("oldest first", icon: "arrow.up", selected: filters.oldestFirst) {
                    filters.oldestFirst = true
                }
            }
            group("actions") {
                action(
                    "copy activity", icon: "doc.on.doc",
                    enabled: !filters.events(model.events).isEmpty, perform: copyActivity)
                action(
                    "clear filters", icon: "line.3.horizontal.decrease",
                    enabled: filters.hasActivityFilters, perform: filters.clearActivity)
            }
        }
    }
    func copyActivity() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        let text = filters.events(model.events).map {
            "\(formatter.string(from: $0.time)) · \($0.text.lowercased())"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    var settingsSidebar: some View {
        Group {
            group("settings") {
                action(
                    "connection", icon: "network", subtitle: endpoint,
                    selected: model.settingsSection == "connection"
                ) { model.settingsSection = "connection" }
                action(
                    "account", icon: "person.crop.circle",
                    subtitle: model.connected ? model.account : model.username,
                    selected: model.settingsSection == "account"
                ) { model.settingsSection = "account" }
                action("application", icon: "macwindow", selected: model.settingsSection == "application") {
                    model.settingsSection = "application"
                }
                action("agents", icon: "terminal", selected: model.settingsSection == "agents") {
                    model.settingsSection = "agents"
                }
            }
            group("components") {
                action("components", icon: "shippingbox", selected: model.settingsSection == "components") {
                    model.settingsSection = "components"
                }
            }
            group("current connection") {
                Text(endpoint).font(.callout).textSelection(.enabled)
                Text(model.connected ? "connected" : "disconnected").font(.caption)
                    .foregroundStyle(MokoTheme.secondaryInk)
                action("copy connection", icon: "doc.on.doc", perform: model.copyConnection)
            }
        }
    }
}
