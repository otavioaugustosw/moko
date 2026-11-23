import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct DatabaseNavigator: View {
    @ObservedObject var browser: DatabaseModel
    var didSelectTable: (() -> Void)?
    @State private var search = ""
    @State private var showSystem = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("search databases or objects", text: $search).textFieldStyle(.roundedBorder).font(
                .callout
            ).accessibilityLabel("search database, table or sql object")
            Toggle("system databases", isOn: $showSystem).font(.caption).toggleStyle(.switch)
                .controlSize(.mini)
            if browser.engine.isPostgreSQL && !browser.database.isEmpty {
                Picker("schema", selection: Binding(get: { browser.schema }, set: browser.selectSchema)) {
                    ForEach(browser.schemas, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(
                            browser.databases.filter { name in
                                (showSystem
                                    || !["mysql", "sys", "performance_schema", "information_schema"]
                                        .contains(name))
                                    && (search.isEmpty || name.localizedCaseInsensitiveContains(search)
                                        || name == browser.database)
                            }, id: \.self
                        ) { name in
                            Button {
                                browser.selectDatabase(name)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(
                                        systemName: name == browser.database
                                            ? "externaldrive.fill" : "externaldrive")
                                    Text(name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.callout).fontWeight(name == browser.database ? .bold : .regular)
                                .foregroundStyle(
                                    name == browser.database ? MokoTheme.selectionInk : MokoTheme.ink
                                )
                                .padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(name).id(name)
                            if name == browser.database {
                                ForEach(
                                    browser.tables.filter {
                                        !$0.isView
                                            && (search.isEmpty
                                                || $0.name.localizedCaseInsensitiveContains(search)
                                                || name.localizedCaseInsensitiveContains(search))
                                    }
                                ) { table in
                                    Button {
                                        browser.loadTable(table.name)
                                        didSelectTable?()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: table.isView ? "eye" : "tablecells")
                                            Text(table.name).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .font(.callout).foregroundStyle(
                                            table.name == browser.table
                                                ? MokoTheme.selectionInk : MokoTheme.ink
                                        )
                                        .fontWeight(table.name == browser.table ? .semibold : .regular)
                                        .padding(.vertical, 8).padding(.leading, 12).contentShape(
                                            Rectangle())
                                    }.buttonStyle(.plain).help(table.name)
                                }
                                DatabaseObjectNavigator(
                                    library: browser.objects, browser: browser,
                                    search: name.localizedCaseInsensitiveContains(search) ? "" : search)
                            }
                        }
                        if browser.databases.isEmpty && !browser.busy {
                            Text("no databases available").font(.caption).foregroundStyle(MokoTheme.secondaryInk)
                                .padding(.vertical, 8)
                        }
                    }
                }.defaultScrollAnchor(.top, for: .sizeChanges)
                    .onChange(of: browser.database) { _, database in
                        // Follow the selected database instead of retaining an offset from a larger list.
                        scroll.scrollTo(database, anchor: .top)
                    }
            }.frame(maxHeight: .infinity)
        }.disabled(browser.busy).foregroundStyle(MokoTheme.ink).tint(MokoTheme.selectionInk)
    }
}
