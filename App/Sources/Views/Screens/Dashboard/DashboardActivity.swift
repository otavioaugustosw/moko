import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
extension Dashboard {

    var activity: some View {
        let events = filters.events(model.events)
        return Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    filters.hasActivityFilters
                        ? "\(events.count) of \(model.events.count) \(model.events.count == 1 ? "event" : "events")"
                        : "\(events.count) \(events.count == 1 ? "event" : "events")"
                ).font(.headline)
                if events.isEmpty {
                    Text(
                        model.events.isEmpty
                            ? "no activity in this session." : "no matching activity."
                    ).foregroundStyle(MokoTheme.secondaryInk)
                }
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.time.formatted(date: .abbreviated, time: .shortened)).font(.caption.monospaced())
                            .foregroundStyle(
                                MokoTheme.secondaryInk
                            ).frame(width: 120, alignment: .leading)
                        Text(event.text.lowercased().asLabel).font(.callout).textSelection(.enabled)
                        Spacer()
                    }
                    if event.id != events.last?.id { Divider() }
                }
            }
        }
    }
}
