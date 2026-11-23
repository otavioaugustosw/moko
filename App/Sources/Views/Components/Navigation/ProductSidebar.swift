import AppKit
import SwiftUI

@available(macOS 26.0, *)
extension MokoContextSidebar {
    var webSidebar: some View {
        PHPProjectSidebar(php: model.phpServer, library: model.phpServer.projects)
    }
    var supportSidebar: some View {
        CreatorProfile()
    }
}
