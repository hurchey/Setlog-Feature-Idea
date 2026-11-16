import SwiftUI
import WidgetKit

/// iOS only ships widgets inside an app. In production that app is Setlog itself;
/// here it's a placeholder.
@main
struct SetlogConceptApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderScreen()
        }
    }
}

struct PlaceholderScreen: View {
    @State private var restarted = false
    @State private var previewingRecap = Store.load()?.previewRecap ?? false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Add the Setlog widget from your Home Screen")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Long-press the Home Screen, tap Edit, then Add Widget, and choose Setlog Concept. Lock Screen widgets are under This hour.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ConceptTag()

            // Restart clears the demo so friends start posting again from the top;
            // the recap switch shows the large widget's end-of-day page without waiting for 22:00.
            VStack(spacing: 10) {
                Button(restarted ? "Demo restarted" : "Restart demo") {
                    Store.reset()
                    WidgetCenter.shared.reloadAllTimelines()
                    restarted = true
                    previewingRecap = false
                }
                .disabled(restarted)

                Button(previewingRecap ? "Back to the live feed" : "Preview tonight's recap") {
                    let state = Store.update { $0.previewRecap.toggle() }
                    WidgetCenter.shared.reloadAllTimelines()
                    previewingRecap = state.previewRecap
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(32)
    }
}
