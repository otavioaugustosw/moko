import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension DatabaseWorkspace {

    var sqlEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(browser.database.isEmpty ? "no default database" : browser.database).font(
                    .caption
                ).foregroundStyle(MokoTheme.secondaryInk)
                Spacer()
                Menu("history") {
                    ForEach(Array(browser.history.enumerated()), id: \.offset) { _, script in
                        Button(String(script.prefix(60)).replacingOccurrences(of: "\n", with: " ")) {
                            browser.sql = script
                        }
                    }
                }.buttonStyle(.plain).disabled(browser.history.isEmpty)
                Button("open .sql") { openSQL() }
                Button("save .sql") { saveSQL() }.disabled(browser.sql.isEmpty)
            }.font(.caption)
            TextEditor(text: $browser.sql).font(.system(.body, design: .monospaced)).frame(
                height: 200
            ).padding(8).background(
                .quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10)
            ).overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.1)))
                .accessibilityLabel("sql editor")
            HStack {
                Button("run sql") { browser.runSQL() }.buttonStyle(MokoButtonStyle(prominent: true))
                    .foregroundStyle(MokoTheme.onAccent).tint(MokoTheme.accent).keyboardShortcut(
                        .return, modifiers: .command
                    ).disabled(
                        browser.busy
                            || browser.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if browser.queryRunning {
                    Button("cancel query", systemImage: "stop.fill") { browser.cancelSQL() }.buttonStyle(
                        MokoButtonStyle())
                }
                Button("refresh structure") { browser.reloadDatabases() }.buttonStyle(MokoButtonStyle())
                    .disabled(browser.busy)
            }
            ForEach(Array(browser.sqlResults.enumerated()), id: \.offset) { index, result in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(
                            "result \(index + 1) · "
                                + (result.fields.isEmpty
                                    ? "\(result.affected) rows affected"
                                    : "\(result.rows.count) rows")
                        ).font(.caption.weight(.semibold))
                        Spacer()
                        if !result.fields.isEmpty {
                            Button("csv") { export(result, filename: "result") }.font(.caption)
                        }
                    }
                    if !result.fields.isEmpty { SQLGrid(result: result).frame(height: 230) }
                    if result.truncated {
                        Text("showing the first 500 rows").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                    }
                    if result.warnings > 0 {
                        Text("\(result.warnings) server warnings").font(.caption).foregroundStyle(
                            MokoTheme.secondaryInk)
                    }
                }
            }
            if !browser.error.isEmpty && !browser.sqlResults.isEmpty {
                Text("the script stopped on an error. previous commands may have been applied").font(
                    .caption
                ).foregroundStyle(MokoTheme.secondaryInk)
            }
        }
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func openSQL() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sql") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { browser.sql = try String(contentsOf: url, encoding: .utf8) } catch {
            formError = "could not open the file"
        }
    }

    func saveSQL() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "query.sql"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try browser.sql.write(to: url, atomically: true, encoding: .utf8) } catch {
            formError = "could not save the file"
        }
    }

    func export(_ result: SQLResult?, filename: String) {
        guard let result else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename + ".csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let quote: (String) -> String = {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows =
            browser.tab == "data" ? Array(result.cells.prefix(browser.pageSize)) : result.cells
        let lines =
            [result.fields.map { quote($0.name) }.joined(separator: ",")]
            + rows.map { row in
                row.enumerated().map { i, cell in
                    cell.hex == nil ? "\\N" : quote(cell.display(binary: result.fields[i].binary))
                }.joined(separator: ",")
            }
        do {
            try (lines.joined(separator: "\n") + "\n").write(
                to: url, atomically: true, encoding: .utf8)
        } catch { formError = "could not export the result" }
    }
}
