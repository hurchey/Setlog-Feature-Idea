import Foundation

// Shared by the app and the widget extension. Add this file to BOTH targets.

// MARK: - Model

struct Friend: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    /// Color used for placeholder cards and avatars (0...1).
    var hue: Double
    /// The emoji this friend reacts with, shown in the trail on a card's corner.
    var reaction: String

    var initial: String { String(name.prefix(1)).uppercased() }
}

/// One 2-second log. The widget shows a still frame; the app keeps the moment.
struct Moment: Codable, Hashable, Identifiable {
    var id = UUID()
    var friendID: String
    var day: String
    var hour: Int
    var createdAt: Date
    /// File name of the still frame inside the shared images folder ("" = none).
    var imageFile: String
    /// Short line the poster wrote, shown under the hour on the card.
    var caption: String = ""
    /// Friend IDs who reacted, in order. Each reacts with their own emoji.
    var reactions: [String] = []
}

/// One Setlog group. In production this lives on Setlog's backend; here it lives in the
/// shared App Group container so every widget and widget button reads the same thing.
struct GroupState: Codable {
    static let maxFriends = 12

    var name: String
    var meID: String
    var friends: [Friend]
    var moments: [Moment]
    /// friend ID -> when I last nudged them.
    var nudges: [String: Date] = [:]
    /// Demo stand-in for the backend: friends' posts scheduled for the next few minutes.
    /// They join `moments` once their `createdAt` has passed.
    var pending: [Moment] = []
    /// Start of the hour the demo posts were last scheduled for.
    var scriptedHour: Date?
    /// Demo switch: show the end-of-day recap now instead of waiting for 22:00.
    var previewRecap = false

    var me: Friend? { friends.first { $0.id == meID } }
    var others: [Friend] { friends.filter { $0.id != meID } }

    func friend(_ id: String) -> Friend? {
        friends.first { $0.id == id }
    }

    func name(of id: String) -> String {
        id == meID ? String(localized: "You") : (friend(id)?.name ?? String(localized: "Someone"))
    }

    // MARK: Hour status

    func moments(day: String, hour: Int) -> [Moment] {
        moments.filter { $0.day == day && $0.hour == hour }
    }

    func hasLogged(_ friendID: String, day: String, hour: Int) -> Bool {
        moments.contains { $0.friendID == friendID && $0.day == day && $0.hour == hour }
    }

    /// Number of different friends who logged in this hour.
    func loggedCount(day: String, hour: Int) -> Int {
        Set(moments(day: day, hour: hour).map(\.friendID)).count
    }

    func loggedNames(day: String, hour: Int) -> [String] {
        friends.filter { hasLogged($0.id, day: day, hour: hour) }.map { name(of: $0.id) }
    }

    /// Friends other than me who haven't logged this hour.
    func missing(day: String, hour: Int) -> [Friend] {
        others.filter { !hasLogged($0.id, day: day, hour: hour) }
    }

    func todaysMoments(day: String) -> [Moment] {
        moments.filter { $0.day == day }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Most recent moment from someone other than me today.
    func latestFriendMoment(day: String) -> Moment? {
        todaysMoments(day: day).first { $0.friendID != meID }
    }

    func wasNudgedThisHour(_ friendID: String, now: Date) -> Bool {
        guard let date = nudges[friendID] else { return false }
        return SetlogTime.day(for: date) == SetlogTime.day(for: now)
            && SetlogTime.hour(for: date) == SetlogTime.hour(for: now)
    }

    func everyoneMissingNudged(now: Date) -> Bool {
        let missing = missing(day: SetlogTime.day(for: now), hour: SetlogTime.hour(for: now))
        return !missing.isEmpty && missing.allSatisfy { wasNudgedThisHour($0.id, now: now) }
    }

    // MARK: Actions

    mutating func toggleMyReaction(momentID: UUID) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        if let mine = moments[index].reactions.firstIndex(of: meID) {
            moments[index].reactions.remove(at: mine)
        } else {
            moments[index].reactions.append(meID)
        }
    }

    /// In production this would send each of them a push. Here it records who was nudged.
    mutating func nudgeEveryoneMissing(at now: Date) {
        for friend in missing(day: SetlogTime.day(for: now), hour: SetlogTime.hour(for: now)) {
            nudges[friend.id] = now
        }
    }

    mutating func addMoment(friendID: String, imageFile: String, at now: Date) {
        let day = SetlogTime.day(for: now)
        let hour = SetlogTime.hour(for: now)
        guard !hasLogged(friendID, day: day, hour: hour) else { return }
        moments.append(Moment(friendID: friendID, day: day, hour: hour, createdAt: now, imageFile: imageFile))
    }

    /// Keeps the shared file small: only today's moments are kept.
    mutating func dropOldMoments(now: Date) {
        let today = SetlogTime.day(for: now)
        moments.removeAll { $0.day != today }
    }

    /// Moves scheduled posts whose time has come into `moments`.
    mutating func releaseDuePosts(now: Date) {
        let due = pending.filter { $0.createdAt <= now }.sorted { $0.createdAt < $1.createdAt }
        pending.removeAll { $0.createdAt <= now }
        for moment in due where !hasLogged(moment.friendID, day: moment.day, hour: moment.hour) {
            moments.append(moment)
        }
    }

    /// The group as it will look at `date`, so a widget timeline can show posts landing on schedule.
    func revealing(upTo date: Date) -> GroupState {
        var copy = self
        copy.releaseDuePosts(now: date)
        return copy
    }

    // MARK: Preview data for widget placeholders and the widget gallery

    static var preview: GroupState {
        let now = Date()
        let day = SetlogTime.day(for: now)
        let hour = SetlogTime.hour(for: now)
        var state = GroupState(name: DemoData.groupName, meID: "me", friends: DemoData.friends, moments: [])
        for (index, friend) in state.others.prefix(2).enumerated() {
            state.moments.append(Moment(friendID: friend.id, day: day, hour: hour,
                                        createdAt: now.addingTimeInterval(Double(-60 * (index + 1))),
                                        imageFile: "",
                                        caption: DemoData.caption(for: friend.id, hour: hour),
                                        reactions: DemoData.reactors(for: friend.id, hour: hour)))
        }
        return state
    }
}

/// Demo group, names, and captions are localized when the group is created, so restart the
/// demo after changing the device language.
enum DemoData {
    static let groupName = String(localized: "Roommates")

    /// Demo friends so the widgets have a group to show. Clearly fake; production uses real members.
    static let friends: [Friend] = [
        Friend(id: "me", name: String(localized: "You"), hue: 0.60, reaction: "❤️"),
        Friend(id: "mina", name: String(localized: "Mina"), hue: 0.95, reaction: "👀"),
        Friend(id: "jae", name: String(localized: "Jae"), hue: 0.08, reaction: "🐶"),
        Friend(id: "sora", name: String(localized: "Sora"), hue: 0.35, reaction: "❤️"),
        Friend(id: "alex", name: String(localized: "Alex"), hue: 0.75, reaction: "😂"),
    ]

    private static let captions: [String: [String]] = [
        "mina": [String(localized: "ramen break 🍜"), String(localized: "snack time 🍪"),
                 String(localized: "library grind 📚"), String(localized: "golden hour ☀️")],
        "jae": [String(localized: "walking the dog 🐶"), String(localized: "on my way home 🚶"),
                String(localized: "coffee run ☕️"), String(localized: "leg day 💪")],
        "sora": [String(localized: "hiii~ 👋"), String(localized: "plant check 🌿"),
                 String(localized: "sunset run 🌇"), String(localized: "nap time 😴")],
        "alex": [String(localized: "studio time 🎧"), String(localized: "late lunch 🥪"),
                 String(localized: "rainy window 🌧️"), String(localized: "game night 🎮")],
    ]

    static func caption(for friendID: String, hour: Int) -> String {
        guard let options = captions[friendID], !options.isEmpty else { return "" }
        return options[hour % options.count]
    }

    /// One or two other friends who hearted a demo post, so cards show reactions.
    static func reactors(for friendID: String, hour: Int) -> [String] {
        let others = friends.map(\.id).filter { $0 != "me" && $0 != friendID }
        guard !others.isEmpty else { return [] }
        let start = (hour + friendID.count) % others.count
        let count = 1 + (hour + friendID.count) % 2
        return (0..<count).map { others[(start + $0) % others.count] }
    }
}

// MARK: - Time

enum SetlogTime {
    static func day(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func hour(for date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    static func startOfHour(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    static func startOfNextHour(after date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
    }

    /// Setlog labels each hourly window by its start on a 24-hour clock, like "15:00".
    static func clock(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    /// 23:00 through 04:59.
    static func isLateNight(_ hour: Int) -> Bool {
        hour >= 23 || hour < 5
    }

    /// From 22:00 the large widget wraps up the day.
    static func isRecapHour(_ hour: Int) -> Bool {
        hour >= 22
    }
}

// MARK: - Deep links

enum DeepLink {
    /// Must match the URL scheme on the app target (Info > URL Types).
    static let scheme = "setlogconcept"
    static let log = URL(string: "setlogconcept://log")!
    /// The day's clips played back to back.
    static let vlog = URL(string: "setlogconcept://vlog")!
}
