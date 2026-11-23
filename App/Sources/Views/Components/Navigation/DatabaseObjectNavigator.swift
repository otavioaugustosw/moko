import SwiftUI

struct DatabaseObjectNavigator: View {
    @ObservedObject var library: DatabaseObjectLibrary
    @ObservedObject var browser: DatabaseModel
    let search: String
    var body: some View {
        ForEach(library.kinds) { kind in
            let entries = library.items.filter {
                $0.kind == kind && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
            }
            DisclosureGroup {
                ForEach(entries) { object in
                    Button {
                        browser.clearTable()
                        library.select(object)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.symbol).frame(width: 16)
                            Text(object.name + (object.kind.callable && library.engine.isPostgreSQL
                                 ? "(" + object.signature + ")" : "")).lineLimit(2)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).padding(.leading, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .foregroundStyle(library.selected?.id == object.id ? MokoTheme.selectionInk : MokoTheme.ink)
                        .fontWeight(library.selected?.id == object.id ? .semibold : .regular)
                        .help(object.name + (object.detail.isEmpty ? "" : " · " + object.detail))
                        .disabled(library.busy || browser.busy)
                }
                if entries.isEmpty {
                    Text("none").font(.caption).foregroundStyle(MokoTheme.secondaryInk).padding(.leading, 24)
                }
            } label: {
                Text(kind.title + " (\(entries.count))").font(.caption.weight(.semibold)).foregroundStyle(
                    MokoTheme.secondaryInk)
            }.padding(.vertical, 4)
        }
    }
}
