import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct Dashboard: View {
    @ObservedObject var model: WorkspaceModel
    @StateObject var filters = PanelFilters()
    @Environment(\.mokoReduceMotion) var reduceMotion
    @State var reveal = false
    @State var newPassword = ""
    @State var confirmation = ""
    @State var editingPassword = false
    @State var revealedCards = 0
    @AppStorage("moko.sidebar.expanded") var sidebarExpanded = true
    @AppStorage("moko.keepInDockOnClose") var keepInDockOnClose = true
    @AppStorage("moko.appearance") var appearance = "system"
    @AppStorage("moko.onboardingCompleted") var onboardingCompleted = false
    @State var showingOnboarding = false
    @State var showingLegalDocuments = false
    let sections = [
        ("overview", "square.grid.2x2"), ("connections", "network"),
        ("web server", "chevron.left.forwardslash.chevron.right"),
        ("databases", "externaldrive"), ("activity", "clock.arrow.circlepath"),
        ("settings", "slider.horizontal.3"),
        ("support", "cup.and.saucer"),
    ]
    var body: some View {
        Group {
            if showingOnboarding {
                OnboardingView(server: model) {
                    onboardingCompleted = true
                    showingOnboarding = false
                }
            } else {
                workspace
            }
        }
        .buttonStyle(MokoButtonStyle()).tint(MokoTheme.selectionInk)
        .frame(minWidth: 900, minHeight: 620).ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        .onAppear { showingOnboarding = !onboardingCompleted }
        .sheet(item: $model.connectionTest) { test in
            ConnectionTestPopup(model: model, initial: test)
        }
        .sheet(isPresented: $showingLegalDocuments) { LegalDocumentsView() }
        .modifier(PHPProjectPresentation(php: model.phpServer, server: model))
        .task(id: showServerCards) {
            guard showServerCards else {
                withAnimation(.easeOut(duration: 0.24)) { revealedCards = 0 }
                return
            }
            if reduceMotion {
                revealedCards = 2
                return
            }
            for count in 1...2 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { revealedCards = count }
                if count < 2 {
                    do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                }
            }
        }
    }
    var workspace: some View {
        // Keep the navigation beside the content at every supported window size.
        HStack(spacing: 0) {
            iconRail
            HStack(spacing: 0) {
                if sidebarExpanded {
                    sidebar.frame(width: model.page == "support" ? 250 : 210)
                    Divider().opacity(0.4)
                }
                contentPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MokoTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(
                    .black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
            .padding(.top, 40).padding(.bottom, 8).padding(.trailing, 8)
        }
        .background(WindowSidebarMaterial())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: sidebarExpanded)
        .frame(minWidth: 900, minHeight: 620).ignoresSafeArea(.container, edges: .top)
        .font(.system(.body, design: .default)).foregroundStyle(MokoTheme.ink).tint(
            MokoTheme.selectionInk
        )
    }
    func toggleSidebar() { sidebarExpanded.toggle() }
    func selectSection(_ title: String) {
        if title == "connections" {
            model.showSessions()
        } else {
            model.page = title
            model.notice = ""
        }
        if title == "databases" || title == "support" { sidebarExpanded = true }
    }
    var iconRail: some View {
        VStack(spacing: 16) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left").font(.system(size: 20)).frame(
                    width: 44, height: 36
                ).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(MokoTheme.secondaryInk).help(
                sidebarExpanded ? "collapse sidebar" : "show sidebar"
            ).accessibilityLabel(sidebarExpanded ? "collapse sidebar" : "show sidebar")
            ForEach(sections, id: \.0) { title, symbol in
                Button {
                    selectSection(title)
                } label: {
                    Image(systemName: symbol).font(
                        .system(size: 20, weight: model.page == title ? .semibold : .regular)
                    ).frame(width: 44, height: 40).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(
                    model.page == title ? MokoTheme.selectionInk : MokoTheme.ink.opacity(0.7)
                ).help(title).accessibilityLabel(title)
            }
            Spacer()
            if !sidebarExpanded {
                Text("moko").font(.system(size: 17, design: .serif)).tracking(-0.6).foregroundStyle(
                    MokoTheme.wordmark
                ).padding(.bottom, 4).accessibilityHidden(true)
            }
        }.padding(.top, 64).padding(.bottom, 16).frame(width: 70, alignment: .center)
    }
    var sidebar: some View {
        MokoContextSidebar(model: model, browser: model.databaseBrowser, filters: filters)
    }
    var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.page != "overview" {
                HStack {
                    Text(model.page).font(.system(size: 28, weight: .semibold))
                    Spacer()
                    if model.working { ProgressView().controlSize(.small) }
                }.padding(.bottom, 16)
            }
            if model.page == "databases" {
                DatabaseWorkspace(server: model, browser: model.databaseBrowser).frame(
                    maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch model.page {
                        case "connections": connectedSessions
                        case "activity": activity
                        case "settings": settings
                        case "web server": WebServerView(server: model)
                        case "support": SupportView()
                        default: overview
                        }
                        TransientNotice(Binding(get: { model.notice.lowercased() }, set: { model.notice = $0 }))
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden).accessibilityIdentifier("workspace-scroll")
            }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16).frame(
            maxWidth: .infinity, maxHeight: .infinity
        ).background(MokoTheme.canvas)
    }
}
