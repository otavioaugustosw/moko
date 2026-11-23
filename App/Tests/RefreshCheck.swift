import Combine
import Foundation

@main struct CheckSilentRefresh {
    static func main() {
        let model = WorkspaceModel()
        model.consume("3306\t26.7.0\troot@localhost\tlocalhost\t/tmp/mysql.sock\nUptime\t100\nThreads_connected\t1\n")
        model.consumeSessions(CommandResult(code: 0, output: ""))
        var events = 0
        let observer = model.objectWillChange.sink { events += 1 }
        for seconds in [108, 116, 124] {
            model.consume(
                "3306\t26.7.0\troot@localhost\tlocalhost\t/tmp/mysql.sock\nUptime\t\(seconds)\nThreads_connected\t1\n")
            model.consumeSessions(CommandResult(code: 0, output: ""))
        }
        guard events == 0 else {
            print("unnecessary visual updates: \(events)")
            exit(1)
        }
        guard model.connections == "0" else { exit(1) }
        withExtendedLifetime(observer) {}
        print("three cycles without unnecessary visual updates; stable count.")
    }
}
