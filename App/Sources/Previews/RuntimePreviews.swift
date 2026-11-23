#if DEBUG
    import SwiftUI

    @available(macOS 26.0, *)
    private struct RuntimePreview: View {
        @StateObject private var server = PreviewFixtures.server(page: "settings")
        @StateObject private var components: RuntimeComponents
        init(state: String) { _components = StateObject(wrappedValue: RuntimeComponents.preview(state)) }
        var body: some View {
            ComponentsView(server: server, components: components).padding(24).frame(width: 680, height: 650)
                .background(MokoTheme.canvas).foregroundStyle(MokoTheme.ink)
        }
    }
    @available(macOS 26.0, *)
    #Preview("components · not installed") { RuntimePreview(state: "ready") }
    @available(macOS 26.0, *)
    #Preview("components · downloading") { RuntimePreview(state: "download") }
    @available(macOS 26.0, *)
    #Preview("components · verifying · dark") { RuntimePreview(state: "verifying").preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("components · cancelled") { RuntimePreview(state: "cancelled") }
    @available(macOS 26.0, *)
    #Preview("components · integrity error · dark") { RuntimePreview(state: "error").preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("components · installed") { RuntimePreview(state: "installed") }
#endif
