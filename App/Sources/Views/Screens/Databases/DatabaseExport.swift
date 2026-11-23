import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension DatabaseWorkspace {
    var databaseExportMenuItem: some View {
        Button(
            exporter.busy ? "cancel export" : "export sql",
            systemImage: exporter.busy ? "xmark" : "square.and.arrow.up"
        ) {
            if exporter.busy { exporter.cancel() } else { chooseDatabaseExport() }
        }.disabled(browser.database.isEmpty || endpoint == nil)
    }
    var databaseExportMenu: some View {
        Menu {
            databaseExportMenuItem
        } label: {
            Image(systemName: "ellipsis").accessibilityLabel("more actions")
        }.menuStyle(.borderlessButton).buttonStyle(.plain).fixedSize()
            .foregroundStyle(MokoTheme.ink).tint(MokoTheme.ink)
    }
    var databaseImportMenuItem: some View {
        Button(
            importer.busy ? "cancel import" : "import sql",
            systemImage: importer.busy ? "xmark" : "square.and.arrow.down"
        ) {
            if importer.busy {
                importer.cancel()
                return
            }
            guard !PreviewRuntime.isActive else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.data, .plainText]
            panel.allowsMultipleSelection = false
            let selected: (NSApplication.ModalResponse) -> Void = { response in
                if response == .OK { importFile = panel.url }
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: selected)
            } else {
                panel.begin(completionHandler: selected)
            }
        }.disabled(browser.database.isEmpty || endpoint == nil || exporter.busy)
    }
    private func chooseDatabaseExport() {
        guard !PreviewRuntime.isActive, let connection = endpoint, !browser.database.isEmpty else { return }
        let database = browser.database, panel = NSSavePanel()
        panel.title = "export database as sql"
        panel.allowedContentTypes = [UTType(filenameExtension: "sql") ?? .plainText]
        panel.nameFieldStringValue = database.replacingOccurrences(of: "/", with: "-") + ".sql"
        let completed: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            exporter.start(connection, database: database, to: destination)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completed)
        } else {
            panel.begin(completionHandler: completed)
        }
    }
}

struct ImportSelection: Identifiable {
    let url: URL
    var id: String { url.path }
}
