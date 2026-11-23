import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension Dashboard {

    var actions: some View {
        HStack(spacing: 8) {
            if !model.usesBundledDatabase && !model.managesServer && !model.controlsExistingMySQL {
                Button("connect") { model.testConnection() }.buttonStyle(MokoButtonStyle())
            } else if model.running {
                Button {
                    model.control("stop")
                } label: {
                    Label("stop", systemImage: "stop.fill")
                }.buttonStyle(MokoButtonStyle())
                Button {
                    model.control("restart")
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .foregroundStyle(MokoTheme.onAccent)
                }.buttonStyle(MokoButtonStyle(prominent: true)).tint(MokoTheme.accent).help("restart database")
                    .accessibilityLabel(
                        "restart database")
            } else {
                Button {
                    model.control("start")
                } label: {
                    Label("start database", systemImage: "play.fill").foregroundStyle(MokoTheme.onAccent)
                }.buttonStyle(MokoButtonStyle(prominent: true)).tint(MokoTheme.accent)
            }
            Menu {
                Button("refresh status") { model.refresh(manual: true) }
                Button("copy connection details", action: model.copyConnection)
                Button("test connection") { model.testConnection() }
                Divider()
                if model.usesBundledDatabase {
                    Button("open database folder") { NSWorkspace.shared.open(model.managedDatabase.dataDirectory) }
                }
            } label: {
                Image(systemName: "ellipsis").accessibilityLabel("more actions").frame(width: 18).foregroundStyle(MokoTheme.ink)
            }.tint(MokoTheme.ink).menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize()
                .accessibilityLabel("more options")
        }.controlSize(.regular).disabled(model.working)
    }

    var overview: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 16) {
            LocalDatabaseOverview(
                server: model, postgres: model.postgresql, mariadb: model.managedDatabase, engine: .postgresql)
            if RuntimePaths.installedMariaDB != nil || model.managedDatabase.running {
                LocalDatabaseOverview(
                    server: model, postgres: model.postgresql, mariadb: model.managedDatabase, engine: .mariadb)
            }
            PHPOverview(php: model.phpServer, server: model) {
                model.page = "web server"
            }
            if !model.profiles.selected.managed { sqlOverview }
            if RuntimePaths.installedMariaDB == nil && !model.managedDatabase.running {
                OptionalMariaDBCard(port: model.managedDatabase.port) {
                    model.page = "settings"
                    model.settingsSection = "components"
                }
            }
        }
    }

    var sqlOverview: some View {
        ServerOverview(
            title: model.engine.rawValue + " · " + model.profiles.selected.name,
            state: model.working ? .yellow : model.light, status: model.displayStatus
        ) {
            actions
        } details: {
            DatabaseServerDetails(
                model: model, showsConnections: showServerCards && revealedCards >= 1,
                transition: cardTransition)
        }
    }

    var showServerCards: Bool {
        model.connected && model.light == .green && model.serviceOperation != "stop"
    }

    var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .offset(x: -28).combined(with: .opacity), removal: .opacity)
    }

    func metric(_ title: String, value: String, icon: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                Text(value).font(.system(size: 20, weight: .semibold, design: .default)).lineLimit(
                    1
                ).minimumScaleFactor(0.6)
            }
        }
    }
}
