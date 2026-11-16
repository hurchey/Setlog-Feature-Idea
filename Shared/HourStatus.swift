import Foundation

// Shared by the app and the widget extension. Add this file to BOTH targets.

/// Everything the widgets show about the current hour for you, worked out from the group at a
/// moment in time. Each widget turns it into its own text, doodles, and buttons.
struct HourStatus {
    /// What the hour needs from you next.
    enum Action: Equatable {
        /// These friends haven't logged, and not all of them have been nudged this hour.
        case nudge([Friend])
        /// Every friend who hasn't logged has been nudged this hour.
        case nudged(Int)
        /// Your turn: every friend has logged and you haven't.
        case log
        /// Everyone, you included, has logged.
        case everyoneIn
    }

    /// Logs in one hour that make it a busy hour.
    private static let busyHourCount = 3

    /// The hour of the day, 0 to 23.
    let hour: Int
    /// Group members who logged this hour, you included, out of `groupSize`.
    let logged: Int
    let groupSize: Int
    let youLogged: Bool
    let action: Action
    let isBusy: Bool
    let isLateNight: Bool
    /// From the start of the hour to its end.
    let countdown: ClosedRange<Date>
    /// Whether the large widget shows the recap instead of the feed.
    let showsRecap: Bool
    private let group: GroupState
    private let day: String

    /// The hour by when it starts, like "14:00".
    var clock: String { SetlogTime.clock(for: hour) }
    /// Friends who logged this hour, not counting you.
    var friendsLogged: Int { youLogged ? logged - 1 : logged }
    var isYourTurn: Bool { action == .log }
    /// Until you log, the countdown is your deadline; after that it runs to the next hour.
    var isYourDeadline: Bool { !youLogged }

    /// How many of the group logged in each of today's 24 hours, for the day bar. Worked out on
    /// demand, since only the widgets that draw the day bar need it.
    var loggedByHour: [Int] {
        var loggers = Array(repeating: Set<String>(), count: 24)
        for moment in group.moments where moment.day == day {
            loggers[moment.hour].insert(moment.friendID)
        }
        return loggers.map(\.count)
    }

    init(group: GroupState, at date: Date) {
        let day = SetlogTime.day(for: date)
        let hour = SetlogTime.hour(for: date)
        let countdown = SetlogTime.startOfHour(for: date)...SetlogTime.startOfNextHour(after: date)
        let youLogged = group.hasLogged(group.meID, day: day, hour: hour)
        let logged = group.loggedCount(day: day, hour: hour)

        self.group = group
        self.day = day
        self.hour = hour
        self.logged = logged
        self.youLogged = youLogged
        self.countdown = countdown
        groupSize = group.friends.count
        action = Self.action(missing: group.missing(day: day, hour: hour), youLogged: youLogged,
                             nudges: group.nudges, during: countdown.lowerBound..<countdown.upperBound)
        isBusy = logged >= Self.busyHourCount
        isLateNight = hour >= 23 || hour < 5
        showsRecap = group.previewRecap || hour >= 22
    }

    private static func action(missing: [Friend], youLogged: Bool, nudges: [String: Date], during hour: Range<Date>) -> Action {
        if missing.isEmpty {
            return youLogged ? .everyoneIn : .log
        }
        let everyoneNudged = missing.allSatisfy { nudges[$0.id].map(hour.contains) ?? false }
        return everyoneNudged ? .nudged(missing.count) : .nudge(missing)
    }
}
