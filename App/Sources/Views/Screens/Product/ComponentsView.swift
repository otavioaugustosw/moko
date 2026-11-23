import SwiftUI

@available(macOS 26.0, *)
struct ComponentsView: View {
    @ObservedObject var server: WorkspaceModel
    @ObservedObject private var components: RuntimeComponents
    @State private var removal = false
    @State private var showingLegal = false
    @State private var upgrade: RuntimePackage?
    @State private var backingUp = false
    init(server: WorkspaceModel, components: RuntimeComponents? = nil) {
        self.server = server
        _components = ObservedObject(wrappedValue: components ?? .shared)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(name: "postgresql · included", value: RuntimePaths.version(of: "libpq"))
                    DetailRow(name: "php · included", value: RuntimePaths.version(of: "php"))
                    if RuntimeComponents.included {
                        DetailRow(name: "mariadb · included", value: RuntimePaths.version(of: "mariadb"))
                    }
                    Button("licenses & sources") { showingLegal = true }
                        .buttonStyle(MokoButtonStyle())
                    Link("runtime sources", destination: URL(string: "https://github.com/otavioaugustosw/moko/releases/tag/runtime-sources-2026-10-12")!)
                }
            }
            if !RuntimeComponents.included {
                MariaDBInstallation(components: components) { package in
                    if components.installed == nil { install(package) } else { upgrade = package }
                }.disabled(backingUp)
            }
            if components.installed != nil && !RuntimeComponents.included {
                Button("remove mariadb component", role: .destructive) { removal = true }
                    .buttonStyle(MokoButtonStyle()).disabled(
                        components.busy || backingUp || server.managedDatabase.busy)
                Text("your databases are kept").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
            }
            if backingUp { ProgressView("backing up database files…") }
        }
        .sheet(isPresented: $showingLegal) { LegalDocumentsView() }
        .sheet(isPresented: $removal) {
            DestructiveReview(
                title: "remove mariadb component",
                message:
                    "the server must be stopped. only the optional executable component will be removed; database files will be kept.",
                actionTitle: "remove", cancel: { removal = false },
                confirm: {
                    guard !server.managedDatabase.running && !server.managedDatabase.busy else {
                        components.error = "stop mariadb before removing its component"
                        removal = false
                        return
                    }
                    do { try components.remove() } catch { components.error = error.localizedDescription }
                    removal = false
                })
        }
        .sheet(item: $upgrade) { package in
            DestructiveReview(
                title: "update mariadb",
                message: "install " + package.version
                    + " after a backup of the data folder. stop mariadb first. major version changes need a dedicated migration.",
                actionTitle: "back up & update", cancel: { upgrade = nil },
                confirm: {
                    backUpAndInstall(package)
                })
        }
    }
    private func install(_ package: RuntimePackage) {
        components.install(package, inactive: { !server.managedDatabase.running && !server.managedDatabase.busy })
    }
    private func backUpAndInstall(_ package: RuntimePackage) {
        guard !backingUp, !server.managedDatabase.running && !server.managedDatabase.busy else {
            components.error = "stop mariadb before updating it"
            upgrade = nil
            return
        }
        backingUp = true
        upgrade = nil
        let source = server.managedDatabase.dataDirectory
        Task {
            do {
                try await Task.detached { try RuntimeBackup.copy(source) }.value
                install(package)
                upgrade = nil
            } catch { components.error = error.localizedDescription }
            backingUp = false
        }
    }
}

@available(macOS 26.0, *)
struct MariaDBInstallation: View {
    @ObservedObject var components: RuntimeComponents
    var install: (RuntimePackage) -> Void
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text("mariadb · optional").font(.headline)
                DetailRow(name: "installed version", value: components.installed?.version ?? "not installed")
                if let installed = components.installed {
                    HStack {
                        if let sources = installed.sourcesURL { Link("corresponding sources", destination: sources) }
                        if let licenses = installed.licensesURL { Link("notices", destination: licenses) }
                    }.font(.caption)
                }
                if components.busy {
                    ProgressView(value: components.progress).accessibilityLabel(components.phase)
                    HStack {
                        Text(components.phase).font(.caption)
                        Spacer()
                        Button("cancel", action: components.cancel).buttonStyle(MokoButtonStyle())
                    }
                } else if components.availability == .unavailable {
                    Text("mariadb is not available to install yet")
                        .font(.callout).foregroundStyle(MokoTheme.secondaryInk)
                        .accessibilityIdentifier("mariadb-unavailable")
                } else {
                    Button("check available versions") { Task { await components.refresh() } }.buttonStyle(
                        MokoButtonStyle())
                    ForEach(components.packages) { package in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    package.version + " · "
                                        + ByteCountFormatter.string(fromByteCount: package.bytes, countStyle: .file))
                                HStack {
                                    Link("license", destination: package.licensesURL)
                                    Link("corresponding sources", destination: package.sourcesURL)
                                }.font(.caption)
                            }
                            Spacer()
                            Button(components.installed == nil ? "install mariadb" : "update") { install(package) }
                                .buttonStyle(MokoButtonStyle(prominent: true))
                                .disabled(components.installed?.id == package.id)
                        }
                    }
                }
                TransientNotice($components.error, isError: true)
                TransientNotice($components.message)
            }
        }
    }
}
