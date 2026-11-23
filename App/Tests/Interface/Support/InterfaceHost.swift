import AppKit
import SwiftUI

@MainActor @main
struct InterfaceHost {
    static var delegate: InterfaceHostDelegate?
    static var minimumSize: NSSize {
        let values = ProcessInfo.processInfo.environment["MOKO_TEST_WINDOW_SIZE"]?.split(separator: "x")
            .compactMap { Double($0) } ?? []
        return values.count == 2 ? NSSize(width: values[0], height: values[1]) : NSSize(width: 940, height: 720)
    }
    static func main() {
        setenv("MOKO_UI_TESTING", "1", 1)
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        delegate = InterfaceHostDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class InterfaceHostDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), entry = NSMenuItem(), edit = NSMenu(title: "edit")
        for (title, action, key) in [
            ("select all", #selector(NSText.selectAll(_:)), "a"),
            ("copy", #selector(NSText.copy(_:)), "c"), ("paste", #selector(NSText.paste(_:)), "v"),
        ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        entry.submenu = edit
        menu.addItem(entry)
        NSApp.mainMenu = menu
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: InterfaceHost.minimumSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "moko interface tests"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InterfaceHarness())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct InterfaceHarness: View {
    @State private var scenario = ProcessInfo.processInfo.environment["MOKO_TEST_SCENARIO"] ?? "screen.overview"
    @State private var theme = "light"
    @State private var large = false
    @State private var reduceMotion = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("fixture", selection: $scenario) {
                    ForEach(InterfaceCatalog.scenarios) { Text($0.id).tag($0.id) }
                }.labelsHidden().accessibilityIdentifier("fixture-selector").frame(width: 230)
                Button("light") { theme = "light" }.accessibilityIdentifier("fixture-light")
                Button("dark") { theme = "dark" }.accessibilityIdentifier("fixture-dark")
                Button(large ? "minimum window" : "large window") { large.toggle() }
                    .accessibilityIdentifier("fixture-size")
                Toggle("reduce motion", isOn: $reduceMotion).accessibilityIdentifier("fixture-reduce-motion")
                Spacer()
            }.padding(8).buttonStyle(MokoButtonStyle()).tint(MokoTheme.selectionInk)
            Divider()
            MokoComponentFixture(scenario: scenario).id(scenario)
                .environment(\.mokoReduceMotion, reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(MokoTheme.canvas).foregroundStyle(MokoTheme.ink)
            .preferredColorScheme(theme == "dark" ? .dark : .light)
            .onChange(of: large) {
                if let window = NSApp.windows.first {
                    window.setContentSize(large ? NSSize(width: 1280, height: 900) : InterfaceHost.minimumSize)
                    window.center()
                }
            }
    }
}
