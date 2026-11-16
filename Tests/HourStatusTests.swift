import Foundation
import Testing
@testable import SetlogConcept

@Suite("Hour status")
struct HourStatusTests {
    /// Every date in a test hangs off this one, so a run that crosses midnight can't mix two days.
    private let base = Date()

    /// Today at `hour`:`minute` on the phone's calendar, which is what the widgets use.
    private func today(_ hour: Int, _ minute: Int = 20) throws -> Date {
        try #require(Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base))
    }

    private func yesterday(_ hour: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: -1, to: today(hour)))
    }

    /// The demo group, with `loggers` having logged in the hour of `date`.
    private func group(loggers: [String], at date: Date, nudged: [String: Date] = [:]) -> GroupState {
        let moments = loggers.map { id in
            Moment(friendID: id, day: SetlogTime.day(for: date), hour: SetlogTime.hour(for: date),
                   createdAt: date, imageFile: "")
        }
        var group = GroupState(name: DemoData.groupName, meID: "me", friends: DemoData.friends, moments: moments)
        group.nudges = nudged
        return group
    }

    private func friends(_ ids: [String]) -> [Friend] {
        DemoData.friends.filter { ids.contains($0.id) }
    }

    @Test("When every friend has logged and you haven't, it's your turn to log")
    func yourTurn() throws {
        let now = try today(14)
        let status = HourStatus(group: group(loggers: ["mina", "jae", "sora", "alex"], at: now), at: now)

        #expect(status.action == .log)
        #expect(status.isYourTurn)
        #expect(status.isYourDeadline)
        #expect(status.logged == 4)
        #expect(status.groupSize == 5)
        #expect(status.friendsLogged == 4)
    }

    @Test("Once you've logged too, everyone's in and the countdown runs to the next hour")
    func everyoneIn() throws {
        let now = try today(14)
        let status = HourStatus(group: group(loggers: ["me", "mina", "jae", "sora", "alex"], at: now), at: now)

        #expect(status.action == .everyoneIn)
        #expect(!status.isYourTurn)
        #expect(!status.isYourDeadline)
        #expect(status.logged == 5)
        #expect(status.friendsLogged == 4)
    }

    @Test("Friends who haven't logged can be nudged")
    func nudge() throws {
        let now = try today(14)
        let status = HourStatus(group: group(loggers: ["mina"], at: now), at: now)

        #expect(status.action == .nudge(friends(["jae", "sora", "alex"])))
    }

    @Test("After nudging everyone who's missing, the hour shows how many were nudged")
    func nudged() throws {
        let now = try today(14)
        let nudges = ["jae": now, "sora": now, "alex": now]
        let status = HourStatus(group: group(loggers: ["mina"], at: now, nudged: nudges), at: now)

        #expect(status.action == .nudged(3))
    }

    @Test("Nudging only some of the missing friends still leaves the Nudge button")
    func partlyNudged() throws {
        let now = try today(14)
        let status = HourStatus(group: group(loggers: ["mina"], at: now, nudged: ["jae": now]), at: now)

        #expect(status.action == .nudge(friends(["jae", "sora", "alex"])))
    }

    @Test("Nudges from an earlier hour, or the same hour yesterday, don't count this hour")
    func oldNudges() throws {
        let now = try today(14)
        for earlier in [try today(13), try yesterday(14)] {
            let nudges = ["jae": earlier, "sora": earlier, "alex": earlier]
            let status = HourStatus(group: group(loggers: ["mina"], at: now, nudged: nudges), at: now)
            #expect(status.action == .nudge(friends(["jae", "sora", "alex"])))
        }
    }

    @Test("Three logs make a busy hour", arguments: [(2, false), (3, true), (4, true)])
    func busyHour(logCount: Int, isBusy: Bool) throws {
        let now = try today(14)
        let loggers = Array(["mina", "jae", "sora", "alex"].prefix(logCount))
        let status = HourStatus(group: group(loggers: loggers, at: now), at: now)

        #expect(status.isBusy == isBusy)
    }

    @Test("Late night runs from 23:00 to 04:59", arguments: [(23, true), (0, true), (4, true), (5, false), (14, false), (22, false)])
    func lateNight(hour: Int, isLateNight: Bool) throws {
        let now = try today(hour)
        #expect(HourStatus(group: group(loggers: [], at: now), at: now).isLateNight == isLateNight)
    }

    @Test("The large widget shows the recap from 22:00, or whenever the preview switch is on")
    func recap() throws {
        let afternoon = try today(14)
        let night = try today(22, 0)
        var previewing = group(loggers: [], at: afternoon)
        previewing.previewRecap = true

        #expect(!HourStatus(group: group(loggers: [], at: afternoon), at: afternoon).showsRecap)
        #expect(HourStatus(group: group(loggers: [], at: night), at: night).showsRecap)
        #expect(HourStatus(group: previewing, at: afternoon).showsRecap)
    }

    @Test("The clock label and countdown cover the hour the time falls in")
    func clockAndCountdown() throws {
        let now = try today(14, 20)
        let status = HourStatus(group: group(loggers: [], at: now), at: now)

        #expect(status.clock == "14:00")
        #expect(status.countdown.lowerBound == (try today(14, 0)))
        #expect(status.countdown.upperBound == (try today(15, 0)))
    }

    @Test("At 23:30 the countdown runs to midnight")
    func countdownAcrossMidnight() throws {
        let now = try today(23, 30)
        let midnight = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: base)))
        let status = HourStatus(group: group(loggers: [], at: now), at: now)

        #expect(status.countdown.upperBound == midnight)
    }

    @Test("The day bar counts how many logged in each of today's hours, and ignores yesterday")
    func dayBar() throws {
        let now = try today(14)
        var state = group(loggers: ["mina", "jae"], at: try today(9))
        state.moments += group(loggers: ["sora"], at: now).moments
        state.moments += group(loggers: ["alex"], at: try yesterday(9)).moments
        let status = HourStatus(group: state, at: now)

        #expect(status.loggedByHour.count == 24)
        #expect(status.loggedByHour[9] == 2)
        #expect(status.loggedByHour[14] == 1)
        #expect(status.loggedByHour.reduce(0, +) == 3)
    }
}
