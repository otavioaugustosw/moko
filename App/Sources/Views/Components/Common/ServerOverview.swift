import SwiftUI

struct ServerOverview<Controls: View, Details: View>: View {
    let title: String
    let state: LightState
    let status: String
    private let controls: Controls
    private let details: Details

    init(
        title: String, state: LightState, status: String,
        @ViewBuilder controls: () -> Controls, @ViewBuilder details: () -> Details
    ) {
        self.title = title
        self.state = state
        self.status = status
        self.controls = controls()
        self.details = details()
    }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.headline).foregroundStyle(MokoTheme.secondaryInk)
                TrafficLight(state: state, width: 165).accessibilityLabel(title + ": " + status)
                Text(status).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                controls
                Divider().overlay(MokoTheme.separator)
                VStack(alignment: .leading, spacing: 12) { details }.font(.callout)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 385, alignment: .topLeading)
        }
    }
}
