import AppKit
import SwiftUI
import XCTest

@testable import mokoInterfaceHost

@MainActor
final class ComponentRenderingTests: XCTestCase {
    func testEveryComponentIsRegistered() throws {
        let resource = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Component Inventory", withExtension: "json"))
        let inventory = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resource))
        let covered = Set(InterfaceCatalog.scenarios.flatMap(\.components))
        let missing = Set(inventory.keys).subtracting(covered)
        XCTAssertTrue(missing.isEmpty, "Components without a rendering scenario: \(missing.sorted())")
        XCTAssertEqual(Set(InterfaceCatalog.scenarios.map(\.id)).count, InterfaceCatalog.scenarios.count)
    }

    func testAllScenariosInBothThemesAndWindowSizes() throws {
        let sizes = [NSSize(width: 900, height: 640), NSSize(width: 1280, height: 900)]
        for scenario in InterfaceCatalog.scenarios {
            for dark in [false, true] {
                for size in sizes {
                    let name = scenario.id + (dark ? " · dark" : " · light") + " · \(Int(size.width))"
                    let view = MokoComponentFixture(scenario: scenario.id)
                        .environment(\.mokoReduceMotion, true)
                        .preferredColorScheme(dark ? .dark : .light)
                        .frame(width: size.width, height: size.height)
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(origin: .zero, size: size)
                    let window = NSWindow(
                        contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = hosting
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.06))
                    hosting.displayIfNeeded()
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), name)
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), name)
                    XCTAssertGreaterThan(data.count, 3000, "Blank component rendering: " + name)
                    XCTAssertGreaterThan(distinctColors(bitmap), 5, "Blank or unpainted component: " + name)
                    XCTAssertEqual(hosting.frame.size, size, "Viewport changed unexpectedly: " + name)
                    let image = NSImage(size: size)
                    image.addRepresentation(bitmap)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.contentView = nil
                    window.close()
                }
            }
        }
    }

    func testBodyAndActionColorContrast() throws {
        for dark in [false, true] {
            let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            appearance.performAsCurrentDrawingAppearance {
                for surface in ["Canvas", "Sidebar", "Surface", "FeatureSurface", "GridRow", "GridAlternateRow"] {
                    for ink in ["Ink", "SecondaryInk", "SelectionInk", "ErrorInk"] {
                        XCTAssertGreaterThanOrEqual(contrast(ink, surface), 4.5, "\(ink)/\(surface), dark=\(dark)")
                    }
                }
                for surface in ["AccentColor", "DisabledAccent", "OnboardingEnd"] {
                    XCTAssertGreaterThanOrEqual(contrast("OnAccent", surface), 4.5, "button label on \(surface)")
                }
                XCTAssertGreaterThanOrEqual(contrast("AccentColor", "OnAccent"), 4.5, "inverted primary label")
            }
        }
    }

    private func distinctColors(_ bitmap: NSBitmapImageRep) -> Int {
        var values = Set<String>()
        // A coarse grid can miss small text in a wide viewport. Sample densely,
        // then stop as soon as enough painted colors have been confirmed.
        for row in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for column in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                values.insert(
                    "\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))"
                )
                if values.count > 5 { return values.count }
            }
        }
        return values.count
    }
    private func contrast(_ foreground: String, _ background: String) -> Double {
        let first = luminance(MokoTheme.native(foreground)), second = luminance(MokoTheme.native(background))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
    private func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        let values = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return Double(values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722)
    }
}
