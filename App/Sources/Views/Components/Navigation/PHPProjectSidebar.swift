import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct PHPProjectSidebar: View {
    @ObservedObject var php: PHPServer
    @ObservedObject var library: PHPProjectLibrary
    @State private var choosingFolder = false
    @State private var unavailableIDs: Set<UUID> = []
    var body: some View {
        let missing = unavailableIDs
        return VStack(alignment: .leading, spacing: 16) {
            Button("add project", systemImage: "plus") { choosingFolder = true }
                .buttonStyle(MokoButtonStyle()).disabled(php.busy)
            if library.items.isEmpty {
                Text("add a folder to run your php project.").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(library.items) { project in projectRow(project, available: !missing.contains(project.id)) }
            }
        }
        .task(id: library.items.map(\.path)) {
            while !Task.isCancelled {
                let missing = Set(library.items.filter { !$0.available }.map(\.id))
                if unavailableIDs != missing { unavailableIDs = missing }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                let project = library.add(url)
                php.requestSwitch(to: project)
            }
        }
    }
    private func projectRow(_ project: PHPProject, available: Bool) -> some View {
        let selected = library.activeID == project.id
        return Button {
            php.requestSwitch(to: project)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "dot.radiowaves.left.and.right" : "folder")
                    .frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                    Text(available ? (selected ? "selected" : "php project") : "folder not found")
                        .font(.caption2).foregroundStyle(MokoTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(php.busy)
        .foregroundStyle(available ? (selected ? MokoTheme.selectionInk : MokoTheme.ink) : MokoTheme.secondaryInk)
        .help(project.path)
        .accessibilityLabel(project.name + (available ? "" : ", folder not found"))
        .contextMenu {
            Button("update folder…") { php.projectPrompt = .init(project: project, kind: .updateFolder) }
            Button("remove project", role: .destructive) { php.requestRemoval(project) }
        }
    }
}
