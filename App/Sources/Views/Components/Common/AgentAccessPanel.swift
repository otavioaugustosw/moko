import AppKit
import SwiftUI

/// Opt-in and setup for AI agents (Model Context Protocol). Shared by settings and onboarding.
@available(macOS 26.0, *)
struct AgentAccessPanel: View {
    var compact = false
    @AppStorage(AgentAccess.enabledKey) private var enabled = false
    @AppStorage(AgentAccess.modeKey) private var mode = AgentAccess.Mode.read.rawValue
    @State private var status = ""
    @State private var working = false
    private var claude: String? { AgentAccess.claudeExecutable() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("let ai agents use moko", isOn: $enabled).accessibilityIdentifier("agents-enabled")
            if enabled {
                Picker("access", selection: $mode) {
                    ForEach(AgentAccess.Mode.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented).frame(maxWidth: 320).accessibilityIdentifier("agents-access")
                if mode == AgentAccess.Mode.write.rawValue {
                    Text("agents can change and delete data").font(.caption).foregroundStyle(MokoTheme.errorInk)
                }
                setup
            }
        }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if claude != nil {
                    Button("add to claude code") { addToClaude() }.buttonStyle(MokoButtonStyle(prominent: true))
                        .disabled(working)
                }
                Button("copy command") {
                    copy(AgentAccess.claudeCommand(executable: AgentAccess.executable), notice: "copied")
                }.buttonStyle(MokoButtonStyle())
                Button("copy json") {
                    copy(AgentAccess.configuration(executable: AgentAccess.executable), notice: "copied")
                }.buttonStyle(MokoButtonStyle())
                if working { ProgressView().controlSize(.small) }
            }
            if !status.isEmpty { Text(status).font(.caption).fixedSize(horizontal: false, vertical: true) }
            if !compact {
                Button("activity log") {
                    if FileManager.default.fileExists(atPath: AgentAccess.logURL.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([AgentAccess.logURL])
                    } else {
                        status = "no activity yet"
                    }
                }.buttonStyle(MokoButtonStyle())
            }
        }
    }
    private func copy(_ text: String, notice: String) {
        guard !PreviewRuntime.isActive else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = notice
    }
    private func addToClaude() {
        guard let claude, !PreviewRuntime.isActive else { return }
        working = true
        status = ""
        let executable = AgentAccess.executable
        DispatchQueue.global().async {
            _ = execute(claude, ["mcp", "remove", "--scope", "user", AgentAccess.serverName])
            let result = execute(claude, AgentAccess.claudeArguments(executable: executable))
            DispatchQueue.main.async {
                working = false
                status =
                    result.code == 0
                    ? "added · restart claude code"
                    : "not added: "
                        + result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }
    }
}
