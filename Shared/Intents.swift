import AppIntents
import Foundation

// Shared by the app and the widget extension. Add this file to BOTH targets.
// These run when someone taps a button on the widget, without opening the app.
// iOS reloads the widget after each one runs.

/// ❤️ a friend's moment straight from the Home Screen.
struct HeartMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "Heart a moment"

    @Parameter(title: "Moment ID")
    var momentID: String

    init() {}

    init(momentID: UUID) {
        self.momentID = momentID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: momentID) else { return .result() }
        Store.update { $0.toggleMyReaction(momentID: id) }
        return .result()
    }
}

/// Nudge everyone who hasn't logged this hour. In production this sends them a push.
struct NudgeMissingIntent: AppIntent {
    static let title: LocalizedStringResource = "Nudge friends who haven't logged"

    init() {}

    func perform() async throws -> some IntentResult {
        let now = Date()
        Store.update(now: now) { $0.nudgeEveryoneMissing(at: now) }
        return .result()
    }
}
