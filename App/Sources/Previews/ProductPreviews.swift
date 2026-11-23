#if DEBUG
    import SwiftUI

    @available(macOS 26.0, *)
    private struct OnboardingPreview: View {
        @StateObject private var model = PreviewFixtures.server()
        var step = 0
        var body: some View {
            OnboardingView(server: model, initialStep: step, completed: {}).frame(width: 1000, height: 720)
        }
    }

    @available(macOS 26.0, *)
    #Preview("onboarding") { OnboardingPreview() }
    @available(macOS 26.0, *)
    #Preview("onboarding · features") { OnboardingPreview(step: 1) }
    @available(macOS 26.0, *)
    #Preview("onboarding · setup") { OnboardingPreview(step: 2) }
    @available(macOS 26.0, *)
    #Preview("onboarding · php choice") { OnboardingPreview(step: 3) }
    @available(macOS 26.0, *)
    #Preview("onboarding · php setup") { OnboardingPreview(step: 4) }
    @available(macOS 26.0, *)
    #Preview("onboarding · dark setup") { OnboardingPreview(step: 2).preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("support · dark") { ScreenPreview(page: "support").preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("overview · dark") { ScreenPreview().preferredColorScheme(.dark) }
    @available(macOS 26.0, *)
    #Preview("php workspace") { ScreenPreview(page: "web server") }
    @available(macOS 26.0, *)
    #Preview("php project · switch") {
        PHPProjectDialog(
            php: PHPServer(preferences: PreviewFixtures.preferences),
            prompt: .init(project: PHPProject(path: "/projects/shop"), kind: .switchProject))
    }
    @available(macOS 26.0, *)
    #Preview("php project · missing folder") {
        PHPProjectDialog(
            php: PHPServer(preferences: PreviewFixtures.preferences),
            prompt: .init(project: PHPProject(path: "/projects/shop"), kind: .missingFolder))
    }
    @available(macOS 26.0, *)
    #Preview("support") { ScreenPreview(page: "support") }
    @available(macOS 26.0, *)
    #Preview("new table") { NewTableView(browser: PreviewFixtures.browser()) }
    @available(macOS 26.0, *)
    #Preview("dark workspace") { ScreenPreview(page: "databases").preferredColorScheme(.dark) }
#endif
