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

    var others: [Friend] { friends.filter { $0.id != meID } }

    func friend(_ id: String) -> Friend? {
        friends.first { $0.id == id }
    }

    func name(of id: String) -> String {
        id == meID ? String(localized: "You") : (friend(id)?.name ?? String(localized: "Someone"))
    }

    // MARK: Who logged when

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

    /// Today's moments from friends, newest first.
    func recentFriendMoments(day: String, limit: Int) -> [Moment] {
        Array(todaysMoments(day: day).filter { $0.friendID != meID }.prefix(limit))
    }

    // MARK: Small widget's photo loop

    static let loopLength = 6
    /// Seconds each moment stays up before the loop moves on.
    static let slideInterval: TimeInterval = 30

    /// The friend a Friend widget follows, by their place in the group; nil means everyone. A group
    /// with fewer friends than the slot has no one there, so that widget shows everyone's moments.
    func friendID(inSlot slot: Int?) -> String? {
        guard let slot, slot < others.count else { return nil }
        return others[slot].id
    }

    /// Today's moments for the loop, newest first: one friend's if `friendID` is set, everyone's otherwise.
    func loopMoments(day: String, friendID: String?) -> [Moment] {
        let moments = todaysMoments(day: day).filter { moment in
            moment.friendID != meID && (friendID == nil || moment.friendID == friendID)
        }
        return Array(moments.prefix(Self.loopLength))
    }

    /// Which moment of the loop shows at `date`. Slides count from the newest post, so a new post
    /// always shows first and the loop moves on by one every `slideInterval`.
    func loopIndex(at date: Date, friendID: String?) -> Int {
        let loop = loopMoments(day: SetlogTime.day(for: date), friendID: friendID)
        guard let newest = loop.first else { return 0 }
        let steps = Int(max(0, date.timeIntervalSince(newest.createdAt)) / Self.slideInterval)
        return steps % loop.count
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
}

// MARK: - Deep links

enum DeepLink {
    /// The `setlogconcept` scheme must match the app target's URL Types (Info > URL Types).
    static let log = URL(string: "setlogconcept://log")!
    /// The day's clips played back to back.
    static let vlog = URL(string: "setlogconcept://vlog")!
}
