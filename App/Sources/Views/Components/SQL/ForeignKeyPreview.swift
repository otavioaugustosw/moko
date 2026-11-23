import AppKit
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct ForeignKeyPreview: View {
    let target: ForeignKeyTarget
    let connection: DatabaseConnection
    let open: () -> Void
    @State private var response: SQLResponse?
    init(
        target: ForeignKeyTarget, connection: DatabaseConnection,
        initialResponse: SQLResponse? = nil, open: @escaping () -> Void
    ) {
        self.target = target
        self.connection = connection
        self.open = open
        _response = State(initialValue: initialResponse)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(target.database + "." + target.table, systemImage: "link").font(.headline)
                .lineLimit(2)
            Text(target.summary).font(.caption).foregroundStyle(MokoTheme.secondaryInk).lineLimit(3)
                .textSelection(.enabled)
            Divider()
            if let response {
                if !response.succeeded {
                    Text("could not load the reference · error \(response.code)").font(
                        .callout
                    ).foregroundStyle(MokoTheme.secondaryInk)
                } else if let result = response.results.first, !result.rows.isEmpty {
                    ForEach(Array(result.fields.prefix(6).enumerated()), id: \.offset) { index, field in
                        HStack(alignment: .top) {
                            Text(field.name).font(.caption).foregroundStyle(MokoTheme.secondaryInk).frame(
                                width: 105, alignment: .leading)
                            Text(
                                String(
                                    result.cells[0][index].display(binary: field.binary).prefix(200)
                                )
                            ).font(.callout).lineLimit(2).textSelection(.enabled)
                        }
                    }
                } else {
                    Text("related row not found").font(.callout).foregroundStyle(MokoTheme.secondaryInk)
                }
            } else {
                ProgressView("loading reference…").controlSize(.small)
            }
            Button("open table", action: open).buttonStyle(MokoButtonStyle(prominent: true)).tint(MokoTheme.accent)
                .foregroundStyle(MokoTheme.onAccent)
        }.padding(16).frame(width: 340).foregroundStyle(MokoTheme.ink)
            .onAppear {
                guard response == nil else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = connection.execute(
                        target.query, database: target.database, maxRows: 1)
                    DispatchQueue.main.async { response = result }
                }
            }
    }
}
