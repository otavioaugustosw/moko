import SwiftUI

struct WelcomeAnimationSettings: Hashable {
    var animationSpeed = 2.45
    var shoutDuration = 3.3
    var dialogueDelay = 3.3
    var characterInterval = 0.09
    var rotationAngle = 20.0
    var horizontalTravel = 8.0
    var fontSize = 30.0
    var peakScale = 2.1
}

@available(macOS 26.0, *)
struct OnboardingWelcome: View {
    private struct Shout {
        var scale: CGFloat = 1
        var offset: CGFloat = 0
        var angle: Double = 0
    }
    private struct PlaybackKey: Hashable {
        var settings: WelcomeAnimationSettings
        var replayToken: Int
        var reduceMotion: Bool
    }
    var settings = WelcomeAnimationSettings()
    var replayToken = 0
    private var durationFactor: Double { settings.shoutDuration / 2.2 / settings.animationSpeed }
    private let dialogue = "i've been waiting for you"
    @State private var visibleCharacters = 0
    @State private var replay = 0
    @Environment(\.mokoReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("hey,")
                    .font(.system(size: settings.fontSize, weight: .semibold))
                    .keyframeAnimator(initialValue: Shout(), trigger: replay) { content, motion in
                        content.scaleEffect(motion.scale).rotationEffect(.degrees(motion.angle)).offset(
                            x: motion.offset)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(reduceMotion ? 1 : settings.peakScale, duration: 0.30 * durationFactor)
                            CubicKeyframe(
                                reduceMotion ? 1 : 1 + (settings.peakScale - 1) * 0.73, duration: 1.35 * durationFactor)
                            CubicKeyframe(1, duration: 0.55 * durationFactor)
                        }
                        KeyframeTrack(\.offset) {
                            LinearKeyframe(
                                reduceMotion ? 0 : -settings.horizontalTravel, duration: 0.25 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : settings.horizontalTravel, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : -settings.horizontalTravel * 0.875, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : settings.horizontalTravel * 0.75, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : -settings.horizontalTravel * 0.5, duration: 0.35 * durationFactor)
                            CubicKeyframe(0, duration: 0.55 * durationFactor)
                        }
                        KeyframeTrack(\.angle) {
                            LinearKeyframe(reduceMotion ? 0 : -settings.rotationAngle, duration: 0.25 * durationFactor)
                            LinearKeyframe(reduceMotion ? 0 : settings.rotationAngle, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : -settings.rotationAngle * 0.83, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : settings.rotationAngle * 0.67, duration: 0.35 * durationFactor)
                            LinearKeyframe(
                                reduceMotion ? 0 : -settings.rotationAngle * 0.5, duration: 0.35 * durationFactor)
                            CubicKeyframe(0, duration: 0.55 * durationFactor)
                        }
                    }
                ZStack(alignment: .leading) {
                    Text(dialogue).hidden()
                    Text(String(dialogue.prefix(visibleCharacters)))
                }.font(.system(size: 28, weight: .semibold))
            }.accessibilityElement(children: .ignore).accessibilityLabel("hey, " + dialogue)
            Image("MokoMascot").resizable().scaledToFit().frame(maxHeight: 250).accessibilityHidden(true)
            Text("your local php and sql workspace").font(.title3)
        }.padding(.horizontal, 12)
            .task(id: PlaybackKey(settings: settings, replayToken: replayToken, reduceMotion: reduceMotion)) {
                if reduceMotion {
                    visibleCharacters = dialogue.count
                    return
                }
                visibleCharacters = 0
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    replay += 1
                    try await Task.sleep(for: .seconds(settings.dialogueDelay / settings.animationSpeed))
                    for count in 1...dialogue.count {
                        try Task.checkCancellation()
                        visibleCharacters = count
                        try await Task.sleep(for: .seconds(settings.characterInterval / settings.animationSpeed))
                    }
                } catch { return }
            }
    }
}
