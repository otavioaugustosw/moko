import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct ConnectionTestPopup: View {
    @ObservedObject var model: WorkspaceModel
    let initial: ConnectionTest
    var test: ConnectionTest { model.connectionTest ?? initial }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("connection test").font(.title2.weight(.semibold))
            Label(test.host + ":" + test.port, systemImage: "network").textSelection(.enabled)
            Label(test.user, systemImage: "person").textSelection(.enabled)
            Divider()
            switch test.phase {
            case .testing:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("testing \(test.host) · \(test.user)").lineLimit(2)
                }
            case .starting:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("starting the server…")
                }
            case .serverStopped:
                Label("server stopped", systemImage: "power").font(.headline)
                Text("start the server to test this connection").font(.callout).foregroundStyle(
                    MokoTheme.secondaryInk)
                if model.managesServer {
                    Button("start and test", action: model.startAndTestConnection).buttonStyle(
                        MokoButtonStyle(prominent: true)
                    ).tint(MokoTheme.accent).foregroundStyle(MokoTheme.onAccent)
                } else {
                    Button("set up local server") {
                        model.connectionTest = nil
                        model.page = "settings"
                        model.settingsSection = "connection"
                    }.buttonStyle(MokoButtonStyle())
                }
            case .success:
                Label("connection successful", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(MokoTheme.selectionInk).font(.headline)
            case let .failure(code, detail):
                Label("connection failed", systemImage: "xmark.circle.fill").foregroundStyle(MokoTheme.errorInk).font(
                    .headline)
                if let code { Text("error \(String(code))").font(.callout.monospaced()) }
                Text(detail).font(.callout).foregroundStyle(MokoTheme.secondaryInk)
            }
            HStack {
                Spacer()
                Button("close") { model.connectionTest = nil }.buttonStyle(MokoButtonStyle(prominent: true)).tint(
                    MokoTheme.accent
                ).foregroundStyle(MokoTheme.onAccent).disabled(test.testing)
            }
        }.padding(24).frame(width: 420).foregroundStyle(MokoTheme.ink)
            .interactiveDismissDisabled(test.testing)
    }
}
