#if DEBUG
    import SwiftUI

    @available(macOS 26.0, *)
    private struct ConnectionPreview: View {
        @StateObject private var model = PreviewFixtures.server()
        let phase: ConnectionTest.Phase
        var body: some View {
            ConnectionTestPopup(
                model: model, initial: .init(host: "127.0.0.1", port: "3306", user: "exemplo", phase: phase)
            )
            .preferredColorScheme(.light).background(Color.white)
        }
    }
    #Preview("connection · testing") { ConnectionPreview(phase: .testing) }
    #Preview("connection · starting") { ConnectionPreview(phase: .starting) }
    #Preview("connection · stopped") { ConnectionPreview(phase: .serverStopped) }
    #Preview("connection · success") { ConnectionPreview(phase: .success) }
    #Preview("connection · error") { ConnectionPreview(phase: .failure(1045, "access denied for user example")) }
#endif
