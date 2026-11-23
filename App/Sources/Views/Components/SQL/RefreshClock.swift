import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct RefreshClock: View {
    @ObservedObject var browser: DatabaseModel
    @Environment(\.mokoReduceMotion) private var reduceMotion
    var body: some View {
        if browser.refreshInterval > 0 {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 60, paused: browser.nextRefreshAt == nil)) { timeline in
                let remaining = browser.nextRefreshAt.map {
                    max(0, $0.timeIntervalSince(timeline.date))
                }
                HStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(MokoTheme.selectionInk.opacity(0.15), lineWidth: 2)
                        Circle().trim(
                            from: 0,
                            to: remaining.map { min(1, $0 / Double(browser.refreshInterval)) } ?? 0
                        )
                        .stroke(
                            MokoTheme.selectionInk,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        ).rotationEffect(.degrees(-90))
                        Image(systemName: remaining == nil ? "pause.fill" : "clock").font(
                            .system(size: 11))
                    }.frame(width: 22, height: 22)
                    Text(remaining.map { "\(Int(ceil($0))) s" } ?? "paused").font(
                        .caption.monospacedDigit()
                    ).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 44, alignment: .leading)
                }.foregroundStyle(MokoTheme.selectionInk)
                    .help(
                        remaining.map { "next refresh in \(Int(ceil($0))) seconds" }
                            ?? "automatic refresh paused during editing or while hidden"
                    )
                    .accessibilityLabel(
                        remaining.map { "next refresh in \(Int(ceil($0))) seconds" }
                            ?? "refresh paused")
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
}
