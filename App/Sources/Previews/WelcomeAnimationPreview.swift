#if DEBUG
    import AppKit
    import SwiftUI

    @available(macOS 26.0, *)
    private struct WelcomeAnimationPreview: View {
        @StateObject private var model = PreviewFixtures.server()
        @State private var settings = WelcomeAnimationSettings()
        @State private var replayToken = 0
        var body: some View {
            HStack(spacing: 0) {
                OnboardingView(server: model, welcomeSettings: settings, welcomeReplayToken: replayToken, completed: {})
                    .frame(width: 1000, height: 720)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("welcomeScreen · animation").font(.headline)
                        Text("changes replay automatically").font(.caption).foregroundStyle(.secondary)
                        control(
                            "animationSpeed", value: $settings.animationSpeed, range: 0.25...3, step: 0.05, unit: "×")
                        control("shoutDuration", value: $settings.shoutDuration, range: 0.3...8, step: 0.1, unit: "s")
                        control("dialogueDelay", value: $settings.dialogueDelay, range: 0...10, step: 0.1, unit: "s")
                        control(
                            "characterInterval", value: $settings.characterInterval, range: 0.01...0.3, step: 0.005,
                            unit: "s")
                        control("rotationAngle", value: $settings.rotationAngle, range: 0...30, step: 1, unit: "°")
                        control(
                            "horizontalTravel", value: $settings.horizontalTravel, range: 0...30, step: 1, unit: "pt")
                        control("fontSize", value: $settings.fontSize, range: 18...72, step: 1, unit: "pt")
                        control("peakScale", value: $settings.peakScale, range: 1...2.5, step: 0.05, unit: "×")
                        Text("animationSpeed divides all times; fontSize changes only hey.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("replay") { replayToken += 1 }
                            Button("reset") {
                                settings = .init()
                                replayToken += 1
                            }
                        }
                        Button("copy values") {
                            let values = """
                                animationSpeed = \(settings.animationSpeed)
                                shoutDuration = \(settings.shoutDuration)
                                dialogueDelay = \(settings.dialogueDelay)
                                characterInterval = \(settings.characterInterval)
                                rotationAngle = \(settings.rotationAngle)
                                horizontalTravel = \(settings.horizontalTravel)
                                fontSize = \(settings.fontSize)
                                peakScale = \(settings.peakScale)
                                """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(values, forType: .string)
                        }
                    }.padding(20)
                }.frame(width: 320, height: 720).background(.background)
            }
        }
        private func control(
            _ name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
            unit: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Text("\(value.wrappedValue, specifier: "%.3f") \(unit)")
                        .monospacedDigit().textSelection(.enabled)
                    Spacer()
                    Stepper(name, value: value, in: range, step: step).labelsHidden()
                }
                Slider(value: value, in: range, step: step).accessibilityLabel(name)
            }
        }
    }

    @available(macOS 26.0, *)
    #Preview("welcomeScreen · animation controls") { WelcomeAnimationPreview() }
#endif
