import AppKit
import Foundation

extension WorkspaceModel {
    func changePassword(_ new: String, confirmation: String) {
        guard !PreviewRuntime.isActive else { return }
        guard !working && !checking else { return }
        guard !new.isEmpty, new == confirmation else {
            notice = "the new password and confirmation must match."
            return
        }
        guard running else {
            notice = "the database is stopped. start it before changing the password."
            return
        }
        working = true
        passwordChanged = false
        notice = "changing password…"
        let secret = password, currentHost = host, currentPort = port, currentUser = username
        let connection = currentConnection
        DispatchQueue.global().async {
            var code: Int32 = 1
            if connection.engine.isPostgreSQL {
                let response = connection.execute(
                    "ALTER ROLE " + PostgreSQLSQL.identifier(currentUser) + " PASSWORD " + PostgreSQLSQL.literal(new))
                DispatchQueue.main.async {
                    self.working = false
                    if response.succeeded {
                        self.password = new
                        self.rememberCredentials()
                        if self.usesBundledDatabase {
                            self.saved = Credentials.save(new, account: self.credentialKey)
                        }
                        self.passwordChanged = true
                        self.notice = "password changed. update applications using this account."
                        self.add("account password changed.")
                        self.refresh()
                    } else {
                        self.notice = response.error.replacingOccurrences(of: new, with: "[redacted]")
                    }
                }
                return
            }
            let output = currentHost.withCString { host in
                currentUser.withCString { user in
                    secret.withCString { old in
                        new.withCString { new in
                            nativeChangePassword(host, UInt32(currentPort) ?? 3306, user, old, new, &code)
                        }
                    }
                }
            }
            if let output { nativeFree(output) }
            let finalCode = code
            DispatchQueue.main.async {
                self.working = false
                if finalCode == 0 {
                    self.password = new
                    self.rememberCredentials()
                    if self.usesBundledDatabase {
                        self.saved = Credentials.save(new, account: self.credentialKey)
                    }
                    self.passwordChanged = true
                    self.notice = "password changed. update applications using this account."
                    self.add("account password changed.")
                    self.refresh()
                } else {
                    let cause: String
                    switch finalCode {
                    case 1045, 3638: cause = "the current password was rejected. check settings → connection."
                    case 2002, 2003:
                        cause = "the server did not respond. check that it is running on the correct port."
                    case 1819:
                        cause =
                            """
                            the password does not meet the server security policy. try a longer password with uppercase and \
                            lowercase letters, numbers and symbols.
                            """
                    case 1820:
                        cause = "the account still requires a temporary password change. the change did not complete."
                    case 1227, 1142: cause = "the account cannot make this change."
                    case 1837: cause = "choose a different password."
                    case 1064: cause = "the server rejected the change format."
                    default: cause = "the database rejected the change. no new password was saved."
                    }
                    self.notice = cause + " (error \(finalCode))"
                    self.add("password change failed. code \(finalCode).")
                }
            }
        }
    }
    func copyConnection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "server: \(host)\nport: \(actualPort == "—" ? port : actualPort)\nuser: \(username)\nauthenticated account: \(account)",
            forType: .string)
        notice = "connection details copied."
    }
}
