import AppIntents
import SwiftUI
import WidgetKit

@main
struct SetlogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MomentsWidget()
        FirstFriendWidget()
        SecondFriendWidget()
        ThirdFriendWidget()
        FourthFriendWidget()
        GroupWidget()
        LockScreenWidget()
    }
}

// MARK: - Timeline

struct SetlogEntry: TimelineEntry {
    let date: Date
    let state: GroupState?
    /// The friend the small widget's loop follows, or nil for everyone.
    var friendID: String?

    var day: String { SetlogTime.day(for: date) }
    var hour: Int { SetlogTime.hour(for: date) }
    var hourEnds: Date { SetlogTime.startOfNextHour(after: date) }
    var hourStarts: Date { SetlogTime.startOfHour(for: date) }
}

/// Timelines shared by the Home Screen and Lock Screen widgets.
enum SetlogTimeline {
    /// Before the group exists (the widget gallery, a fresh install), the snapshot shows the preview group.
    static func snapshot(slot: Int?) -> SetlogEntry {
        let now = Date()
        let state = Store.load()?.revealing(upTo: now) ?? .preview
        return SetlogEntry(date: now, state: state, friendID: state.friendID(inSlot: slot))
    }

    /// One entry now, one as each scripted friend post lands, and one at the top of the next hour,
    /// when the new logging window opens. The countdown text ticks on its own, so no per-minute
    /// entries are needed. Small widgets also get an entry per slide of their photo loop, planned
    /// through to the top of the hour: asking for a fresh timeline more often than hourly runs past
    /// WidgetKit's daily reload budget, and the loop would freeze.
    static func make(family: WidgetFamily, slot: Int?) -> Timeline<SetlogEntry> {
        let now = Date()
        let next = SetlogTime.startOfNextHour(after: now)
        let state = Store.update(now: now)
        let friendID = state.friendID(inSlot: slot)
        let postTimes = state.pending.map(\.createdAt).filter { $0 > now && $0 < next }
        var dates = [now] + postTimes + [next]

        let loop = state.revealing(upTo: next).loopMoments(day: SetlogTime.day(for: now), friendID: friendID)
        if family == .systemSmall, loop.count > 1 {
            let slideCount = Int(next.timeIntervalSince(now) / GroupState.slideInterval)
            dates += (1..<max(slideCount, 1)).map { now.addingTimeInterval(Double($0) * GroupState.slideInterval) }
        }

        let entries = Set(dates).sorted().map {
            SetlogEntry(date: $0, state: state.revealing(upTo: $0), friendID: friendID)
        }
        return Timeline(entries: entries, policy: .after(next))
    }
}

/// Every Setlog widget's provider. Friend widgets pass their slot; the rest show everyone.
struct SetlogProvider: TimelineProvider {
    /// 0 for the group's first friend, 1 for the second, and so on.
    var slot: Int?

    func placeholder(in context: Context) -> SetlogEntry {
        SetlogEntry(date: Date(), state: .preview, friendID: GroupState.preview.friendID(inSlot: slot))
    }

    func getSnapshot(in context: Context, completion: @escaping (SetlogEntry) -> Void) {
        completion(SetlogTimeline.snapshot(slot: slot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SetlogEntry>) -> Void) {
        completion(SetlogTimeline.make(family: context.family, slot: slot))
    }
}

// MARK: - Home Screen widgets

/// Small: loops through everyone's moments today, on its own. Friend by friend is the Friend
/// widgets' job, so this one stays out of their stack.
struct MomentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetlogMoments", provider: SetlogProvider()) { entry in
            GroupWidgetView(entry: entry)
                .widgetURL(DeepLink.log)
        }
        .configurationDisplayName("Moments")
        .description("Loop through everyone's moments today.")
        .supportedFamilies([.systemSmall])
    }
}

/// Small: loops through one friend's moments today. Widgets can't be told apart without settings,
/// so each friend in the group gets their own widget, ready to stack with no setup.
private func friendMomentsConfiguration(slot: Int, name: LocalizedStringResource) -> some WidgetConfiguration {
    StaticConfiguration(kind: "SetlogFriend\(slot + 1)", provider: SetlogProvider(slot: slot)) { entry in
        GroupWidgetView(entry: entry)
            .widgetURL(DeepLink.log)
    }
    .configurationDisplayName(name)
    .description("One friend's moments today, on a loop. Stack the Friend widgets to swipe between friends.")
    .supportedFamilies([.systemSmall])
}

struct FirstFriendWidget: Widget {
    var body: some WidgetConfiguration {
        friendMomentsConfiguration(slot: 0, name: "Friend 1")
    }
}

struct SecondFriendWidget: Widget {
    var body: some WidgetConfiguration {
        friendMomentsConfiguration(slot: 1, name: "Friend 2")
    }
}

struct ThirdFriendWidget: Widget {
    var body: some WidgetConfiguration {
        friendMomentsConfiguration(slot: 2, name: "Friend 3")
    }
}

struct FourthFriendWidget: Widget {
    var body: some WidgetConfiguration {
        friendMomentsConfiguration(slot: 3, name: "Friend 4")
    }
}

/// Medium and large: the group's feed, the hour's status, and nudges.
struct GroupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetlogGroup", provider: SetlogProvider()) { entry in
            GroupWidgetView(entry: entry)
                .widgetURL(DeepLink.log)
        }
        .configurationDisplayName("Your Setlog group")
        .description("See your friends' latest moment, heart it, and nudge whoever hasn't logged this hour.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct GroupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SetlogEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .systemSmall:
                small(state)
            case .systemLarge where state.previewRecap || SetlogTime.isRecapHour(entry.hour):
                recap(state)
                    .containerBackground(for: .widget) { DoodlePaper() }
            case .systemLarge:
                large(state)
                    .containerBackground(for: .widget) { DoodlePaper() }
            default:
                medium(state)
                    .containerBackground(for: .widget) { DoodlePaper() }
            }
        } else {
            Text("Open Setlog to set up your group.")
                .font(.hand(15))
                .foregroundStyle(Palette.ink)
                .containerBackground(for: .widget) { DoodlePaper() }
        }
    }

    // Moments fade in place rather than slide, so only a swipe through the stack changes friends.
    private func small(_ state: GroupState) -> some View {
        let loop = state.loopMoments(day: entry.day, friendID: entry.friendID)
        let moment = loop.isEmpty ? nil : loop[state.loopIndex(at: entry.date, friendID: entry.friendID)]
        let followed = entry.friendID.flatMap { state.friend($0) }
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        return ZStack {
            if let moment {
                // Bottom padding lifts the hour and caption clear of the pill and reaction trail.
                MomentOverlay(moment: moment, name: state.name(of: moment.friendID), timeSize: 24)
                    .padding(.bottom, 18)
                    .id(moment.id)
                    .transition(.opacity)
            } else if let followed {
                VStack(alignment: .leading, spacing: 2) {
                    Text(followed.name)
                        .font(.hand(17))
                    Text("No logs yet today")
                        .font(.hand(15, bold: false))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack(alignment: .bottom) {
                HStack(spacing: 3) {
                    Text("\(logged)/\(state.friends.count) in")
                        .contentTransition(.numericText(value: Double(logged)))
                    statusDoodles(logged: logged, size: 13)
                }
                .font(.hand(14))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .sketchPill()
                Spacer(minLength: 0)
                if let moment {
                    heartTrail(state: state, moment: moment, size: 22)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .overlay(alignment: .topTrailing) {
            ZStack {
                Doodle(kind: .sparkle, size: 13)
                    .offset(x: -2, y: -2)
                Doodle(kind: .sparkle, size: 8)
                    .offset(x: -16, y: 10)
            }
        }
        .containerBackground(for: .widget) {
            // Color.clear takes the widget's size, so the frame isn't stretched to the photo's.
            Color.clear
                .overlay(MomentImage(moment: moment, friend: moment.flatMap { state.friend($0.friendID) } ?? followed))
                .overlay(
                    SketchRoundedRect(cornerRadius: 20, wobble: 1.4, seed: 4)
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .padding(6)
                )
        }
    }

    // Medium: the two latest moments as tilted, stacked feed cards on Setlog's paper
    // background, with the hour's status beside them.
    private func medium(_ state: GroupState) -> some View {
        let recent = state.recentFriendMoments(day: entry.day, limit: 2)
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        let meLogged = state.hasLogged(state.meID, day: entry.day, hour: entry.hour)

        return HStack(spacing: 14) {
            ZStack {
                if recent.count > 1 {
                    card(state: state, moment: recent[1], interactive: false)
                        .scaleEffect(0.9)
                        .rotationEffect(.degrees(7))
                        .offset(x: 14, y: -3)
                        .id(recent[1].id)
                        .transition(.opacity)
                }
                if let latest = recent.first {
                    // A new post lands on top of the stack.
                    card(state: state, moment: latest, interactive: true)
                        .overlay(alignment: .topTrailing) {
                            Doodle(kind: .heart, size: 20)
                                .offset(x: 9, y: -9)
                        }
                        .rotationEffect(.degrees(-4))
                        .offset(x: -6, y: 2)
                        .id(latest.id)
                        .transition(.push(from: .top))
                }
            }
            .frame(width: 124)

            VStack(alignment: .leading, spacing: 5) {
                groupPill(state.name)

                HStack(spacing: 3) {
                    Text("\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(state.friends.count) logged")
                        .font(.hand(14))
                        .foregroundStyle(Palette.muted)
                        .contentTransition(.numericText(value: Double(logged)))
                    statusDoodles(logged: logged, size: 13)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(meLogged ? "Next in" : "Log in")
                        .font(.hand(14))
                        .foregroundStyle(Palette.muted)
                    Text(timerInterval: entry.hourStarts...entry.hourEnds, countsDown: true)
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .monospacedDigit()
                        .widgetAccentable()
                }

                HourBar(state: state, day: entry.day, currentHour: entry.hour, height: 10, color: Palette.purple)

                Spacer(minLength: 0)
                hourAction(state: state)
            }
            .foregroundStyle(Palette.ink)
        }
        .overlay(alignment: .bottomTrailing) {
            Doodle(kind: .puppy, size: 24)
                .rotationEffect(.degrees(-8))
                .offset(x: 10, y: 10)
        }
    }

    // Large: Setlog's feed, the three latest moments as staggered, tilted cards, with the
    // hour's status above and the countdown and nudge below. Sized for the Today View.
    private func large(_ state: GroupState) -> some View {
        let recent = state.recentFriendMoments(day: entry.day, limit: 3)
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        let meLogged = state.hasLogged(state.meID, day: entry.day, hour: entry.hour)
        let stagger: [(x: CGFloat, degrees: Double)] = [(-16, -2.5), (16, 2), (-10, -1.5)]

        return VStack(spacing: 10) {
            HStack(spacing: 3) {
                groupPill(state.name)
                Spacer(minLength: 8)
                Text("\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(state.friends.count) logged")
                    .font(.hand(14))
                    .foregroundStyle(Palette.muted)
                    .contentTransition(.numericText(value: Double(logged)))
                statusDoodles(logged: logged, size: 14)
            }

            VStack(spacing: -6) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, moment in
                    card(state: state, moment: moment, size: CGSize(width: 250, height: 76),
                         timeSize: 17, trailSize: 14, interactive: true)
                        .overlay(alignment: .topTrailing) {
                            if index == 0 {
                                Doodle(kind: .heart, size: 20)
                                    .offset(x: 8, y: -9)
                            }
                        }
                        .rotationEffect(.degrees(stagger[index].degrees))
                        .offset(x: stagger[index].x)
                        .transition(.push(from: .top))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Doodle(kind: .puppy, size: 30)
                    .rotationEffect(.degrees(8))
                    .offset(x: 6, y: 12)
            }
            .frame(maxHeight: .infinity)

            HourBar(state: state, day: entry.day, currentHour: entry.hour, height: 10, color: Palette.purple)

            HStack {
                hourAction(state: state)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(meLogged ? "Next in" : "Log in")
                        .font(.hand(14))
                        .foregroundStyle(Palette.muted)
                    Text(timerInterval: entry.hourStarts...entry.hourEnds, countsDown: true)
                        .font(.system(size: 20, weight: .black).width(.expanded))
                        .monospacedDigit()
                        .widgetAccentable()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 86, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(Palette.ink)
    }

    // Recap: from 22:00 the large widget turns the day into a scrapbook page of its moments,
    // Setlog's "keep your day as a vlog" at a glance, with a link to play the day back.
    private func recap(_ state: GroupState) -> some View {
        let today = Array(state.todaysMoments(day: entry.day).reversed())
        let shown = Array(today.suffix(9))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                groupPill(state.name)
                Spacer(minLength: 8)
                Doodle(kind: .moon, size: 20)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Today in \(today.count) logs")
                    .font(.hand(28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                SquiggleShape()
                    .stroke(Palette.flame, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 130, height: 7)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, moment in
                    Color.clear
                        .frame(height: 50)
                        .overlay(MomentImage(moment: moment, friend: state.friend(moment.friendID)))
                        .overlay {
                            Text(SetlogTime.clock(for: moment.hour))
                                .font(.system(size: 11, weight: .black).width(.expanded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.cardEdge, lineWidth: 2))
                        .overlay(
                            SketchRoundedRect(cornerRadius: 11, wobble: 0.8, seed: Double(index))
                                .stroke(Palette.ink, lineWidth: 1.2)
                                .padding(-1.5)
                        )
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2 : 2))
                }
            }

            HourBar(state: state, day: entry.day, height: 10, color: Palette.purple)

            HStack(alignment: .bottom) {
                Link(destination: DeepLink.vlog) {
                    HStack(spacing: 4) {
                        Doodle(kind: .sparkle, size: 14)
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Watch today's vlog")
                                .font(.hand(14))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .sketchPill()
                    }
                }
                Spacer(minLength: 0)
                Doodle(kind: .puppy, size: 28)
                    .rotationEffect(.degrees(-6))
            }
        }
        .foregroundStyle(Palette.ink)
    }

    /// One feed card: photo, name, hour and caption, white border. Only interactive cards take taps.
    private func card(state: GroupState, moment: Moment, size: CGSize = CGSize(width: 108, height: 122),
                      timeSize: CGFloat = 16, trailSize: CGFloat = 16, interactive: Bool) -> some View {
        MomentImage(moment: moment, friend: state.friend(moment.friendID))
            .frame(width: size.width, height: size.height)
            .overlay {
                MomentOverlay(moment: moment, name: state.name(of: moment.friendID), timeSize: timeSize)
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                if interactive {
                    heartTrail(state: state, moment: moment, size: trailSize)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.cardEdge, lineWidth: 2.5))
            .overlay(
                SketchRoundedRect(cornerRadius: 17, wobble: 1, seed: Double(moment.id.uuid.0))
                    .stroke(Palette.ink, lineWidth: 1.4)
                    .padding(-1.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    /// The group name in a white pill with a couple of sparkles, like a sticker on the page.
    private func groupPill(_ name: String) -> some View {
        Text(name)
            .font(.hand(16))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .sketchPill()
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Doodle(kind: .sparkle, size: 11)
                        .offset(x: 10, y: -7)
                    Doodle(kind: .sparkle, size: 7)
                        .offset(x: 18, y: 3)
                }
            }
    }

    /// Flames once the hour gets busy, a moon in the small hours.
    @ViewBuilder
    private func statusDoodles(logged: Int, size: CGFloat) -> some View {
        if logged >= GroupState.busyHourCount {
            Doodle(kind: .flame, size: size)
        }
        if SetlogTime.isLateNight(entry.hour) {
            Doodle(kind: .moon, size: size)
        }
    }

    private func heartTrail(state: GroupState, moment: Moment, size: CGFloat) -> some View {
        let mine = moment.reactions.contains(state.meID)
        let others = moment.reactions.filter { $0 != state.meID }.compactMap { state.friend($0)?.reaction }
        return Button(intent: HeartMomentIntent(momentID: moment.id)) {
            ReactionTrail(others: others, mine: mine, size: size)
        }
        .buttonStyle(.plain)
    }

    /// What the hour needs next: nudge whoever's missing, or log once everyone else is in.
    @ViewBuilder
    private func hourAction(state: GroupState) -> some View {
        let missing = state.missing(day: entry.day, hour: entry.hour)
        if missing.isEmpty && state.hasLogged(state.meID, day: entry.day, hour: entry.hour) {
            HStack(spacing: 5) {
                Doodle(kind: .star, size: 20)
                Text("Everyone's in")
                    .font(.hand(14))
            }
        } else if missing.isEmpty {
            // Everyone else is in, so the only thing left is my log. Opens Setlog's camera.
            Link(destination: DeepLink.log) {
                HStack(spacing: 4) {
                    Doodle(kind: .star, size: 20)
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Log \(SetlogTime.clock(for: entry.hour))")
                            .font(.hand(14))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .sketchPill()
                }
            }
        } else if state.everyoneMissingNudged(now: entry.date) {
            HStack(spacing: 5) {
                Doodle(kind: .envelope, size: 16)
                Text("Nudged \(missing.count)")
                    .font(.hand(14))
                    .foregroundStyle(Palette.muted)
            }
        } else {
            // Avatars beside a white pill, like Setlog's comment bubbles. A nudge is a little note.
            Button(intent: NudgeMissingIntent()) {
                HStack(spacing: 4) {
                    HStack(spacing: -6) {
                        ForEach(missing.prefix(3)) { friend in
                            Avatar(friend: friend, size: 20)
                                .overlay(Circle().stroke(Palette.paper, lineWidth: 1.5))
                        }
                    }
                    HStack(spacing: 4) {
                        Doodle(kind: .envelope, size: 15)
                        Text("Nudge \(missing.count)")
                            .font(.hand(14))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .sketchPill()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Lock Screen widgets

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetlogLockScreen", provider: SetlogProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(DeepLink.log)
        }
        .configurationDisplayName("This hour")
        .description("How many friends logged this hour, and how long you have left.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SetlogEntry

    var body: some View {
        let state = entry.state ?? .preview
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        let total = state.friends.count
        let meLogged = state.hasLogged(state.meID, day: entry.day, hour: entry.hour)

        switch family {
        case .accessoryCircular:
            // A hand-drawn ring: the faint loop is the whole group, the bold stroke is who's logged.
            ZStack {
                AccessoryWidgetBackground()
                SketchRoundedRect(wobble: 0.8, seed: 21)
                    .stroke(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(4)
                SketchRoundedRect(wobble: 0.8, seed: 21)
                    .trim(from: 0, to: Double(logged) / Double(max(total, 1)))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(4)
                    .widgetAccentable()
                VStack(spacing: -2) {
                    Doodle(kind: hourDoodle(state: state, logged: logged, meLogged: meLogged), size: 15, lineArt: true)
                    Text("\(logged)/\(total)")
                        .font(.hand(17))
                }
            }

        case .accessoryInline:
            if let latest = state.latestFriendMoment(day: entry.day) {
                Text("\(state.name(of: latest.friendID)) posted · \(logged)/\(total) in")
            } else {
                Text("\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(total) logged")
            }

        default:
            // The doodle shares only the first line, so the count and countdown get the full width.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if let latest = state.latestFriendMoment(day: entry.day) {
                        Text("\(state.name(of: latest.friendID)) posted")
                            .font(.hand(16))
                            .widgetAccentable()
                        Text(latest.createdAt, style: .relative)
                            .font(.hand(12, bold: false))
                    } else {
                        Text("Setlog · \(SetlogTime.clock(for: entry.hour))")
                            .font(.hand(16))
                            .widgetAccentable()
                    }
                    Spacer(minLength: 0)
                    Doodle(kind: hourDoodle(state: state, logged: logged, meLogged: meLogged), size: 18, lineArt: true)
                        .widgetAccentable()
                }
                Text(meLogged
                     ? "\(SetlogTime.clock(for: entry.hour)) · you + \(max(logged - 1, 0)) logged"
                     : "\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(total) logged")
                    .font(.hand(14))
                HStack(spacing: 3) {
                    Text(timerInterval: entry.hourStarts...entry.hourEnds, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(meLogged ? "to next log" : "left to log")
                        .font(.hand(13))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    /// The hour's mood: the star when everyone else is in and it's your turn, flames when it's busy,
    /// the moon late at night, and sparkles otherwise.
    private func hourDoodle(state: GroupState, logged: Int, meLogged: Bool) -> Doodle.Kind {
        if !meLogged && state.missing(day: entry.day, hour: entry.hour).isEmpty {
            return .star
        }
        if logged >= GroupState.busyHourCount {
            return .flame
        }
        return SetlogTime.isLateNight(entry.hour) ? .moon : .sparkle
    }
}
