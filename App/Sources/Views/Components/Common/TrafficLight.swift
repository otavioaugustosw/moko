import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrafficLight: View {
    var state: LightState
    var width: CGFloat = 180
    // Catalog images have their horizontal orientation baked into their pixels.
    private static let artwork: [LightState: NSImage] = {
        var result: [LightState: NSImage] = [:]
        for (state, name) in [(LightState.red, "TrafficRed"), (.yellow, "TrafficYellow"), (.green, "TrafficGreen")] {
            guard let image = NSImage(named: name) else { continue }
            image.isTemplate = false
            result[state] = image
        }
        return result
    }()
    var body: some View {
        Group {
            if let image = Self.artwork[state] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: width, height: width)
            }
        }.frame(width: width, height: width * 0.44).clipped()
            .accessibilityLabel(state.title)
    }
}
