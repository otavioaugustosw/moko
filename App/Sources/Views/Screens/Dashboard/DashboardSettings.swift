import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension Dashboard {

    var connection: some View {
        ConnectionProfileSettings(server: model, profiles: model.profiles)
    }

    func input(_ name: String, text: Binding<String>) -> some View {
        HStack {
            Text(name).frame(width: 90, alignment: .leading).foregroundStyle(MokoTheme.secondaryInk)
            TextField(name, text: text).textFieldStyle(.roundedBorder)
        }
    }

    var account: some View {
        VStack(spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    DetailRow(
                        name: "account", value: model.connected ? model.account : model.username)
                    Text(
                        model.password.isEmpty
                            ? "no password provided"
                            : (model.saved
                                ? "password saved in keychain" : "password used only for this session")
                    ).font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                    HStack {
                        Text("current password").foregroundStyle(MokoTheme.secondaryInk)
                        Spacer()
                        Text(
                            model.password.isEmpty
                                ? "—" : (reveal ? model.password : "••••••••••••")
                        ).font(.system(.body, design: .monospaced)).textSelection(.disabled)
                        Button {
                            reveal.toggle()
                        } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye")
                        }.buttonStyle(MokoButtonStyle()).disabled(model.password.isEmpty).help(
                            reveal ? "hide password" : "show password"
                        ).accessibilityLabel(reveal ? "hide password" : "show password")
                    }
                    Button(editingPassword ? "cancel change" : "change password") {
                        editingPassword.toggle()
                        newPassword = ""
                        confirmation = ""
                        model.notice = ""
                    }.buttonStyle(MokoButtonStyle())
                }
            }
            if editingPassword {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        SecureField("new password", text: $newPassword).textFieldStyle(.roundedBorder)
                        SecureField("confirm new password", text: $confirmation).textFieldStyle(
                            .roundedBorder)
                        if !model.running {
                            Button("start the server to change the password") { model.control("start") }
                                .buttonStyle(MokoButtonStyle(prominent: true))
                        }
                        Button("save new password") {
                            model.changePassword(newPassword, confirmation: confirmation)
                        }.buttonStyle(MokoButtonStyle(prominent: true)).disabled(
                            model.working || !model.running || newPassword.isEmpty
                                || newPassword != confirmation)
                    }.onChange(of: model.passwordChanged) {
                        if model.passwordChanged {
                            newPassword = ""
                            confirmation = ""
                            editingPassword = false
                        }
                    }
                }
            }
        }
    }

    var settings: some View {
        VStack(spacing: 16) {
            HStack {
                Text(model.settingsSection).font(.headline)
                Spacer()
                if !sidebarExpanded {
                    Picker("section", selection: $model.settingsSection) {
                        Text("connection").tag("connection")
                        Text("account").tag("account")
                        Text("application").tag("application")
                        Text("agents").tag("agents")
                        Text("components").tag("components")
                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                }
            }
            switch model.settingsSection {
            case "account": account
            case "application": applicationSettings
            case "agents": Surface { AgentAccessPanel() }
            case "components": ComponentsView(server: model)
            default: connection
            }
        }
    }

    var applicationSettings: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("keep in dock when the window is closed", isOn: $keepInDockOnClose)
                HStack {
                    Text("appearance").foregroundStyle(MokoTheme.secondaryInk)
                    AppearancePicker(selection: $appearance).frame(maxWidth: 320)
                }
                Button("show onboarding") { showingOnboarding = true }.buttonStyle(MokoButtonStyle())
                Button("legal & credits") { showingLegalDocuments = true }.buttonStyle(MokoButtonStyle())
            }
        }
    }
}
