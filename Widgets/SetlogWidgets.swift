import AppIntents
import SwiftUI
import WidgetKit

@main
struct SetlogWidgetBundle: WidgetBundle {
    var body: some Widget {
        GroupWidget()
        LockScreenWidget()
    }
}

// MARK: - Timeline

struct SetlogEntry: TimelineEntry {
    let date: Date
    let state: GroupState?

    var day: String { SetlogTime.day(for: date) }
    var hour: Int { SetlogTime.hour(for: date) }
    var hourEnds: Date { SetlogTime.startOfNextHour(after: date) }
    var hourStarts: Date { SetlogTime.startOfHour(for: date) }
}

struct SetlogProvider: TimelineProvider {
    func placeholder(in context: Context) -> SetlogEntry {
        SetlogEntry(date: Date(), state: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SetlogEntry) -> Void) {
        let now = Date()
        completion(SetlogEntry(date: now, state: Store.load()?.revealing(upTo: now) ?? .preview))
    }

    /// One entry now, one as each scripted friend post lands, and one at the top of the next hour,
    /// when the new logging window opens. The countdown text ticks on its own, so no per-minute
    /// entries are needed.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SetlogEntry>) -> Void) {
        let now = Date()
        let next = SetlogTime.startOfNextHour(after: now)
        let state = Store.loadCurrent(now: now)
        let postTimes = state.pending.map(\.createdAt).filter { $0 > now && $0 < next }.sorted()
        let entries = ([now] + postTimes + [next]).map { SetlogEntry(date: $0, state: state.revealing(upTo: $0)) }
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - Home Screen widget

struct GroupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetlogGroup", provider: SetlogProvider()) { entry in
            GroupWidgetView(entry: entry)
                .widgetURL(DeepLink.log)
        }
        .configurationDisplayName("Your Setlog group")
        .description("See your friends' latest moment, heart it, and nudge whoever hasn't logged this hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
                    .containerBackground(for: .widget) { Palette.paper }
            case .systemLarge:
                large(state)
                    .containerBackground(for: .widget) { Palette.paper }
            default:
                medium(state)
                    .containerBackground(for: .widget) { Palette.paper }
            }
        } else {
            Text("Open Setlog to set up your group.")
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .containerBackground(for: .widget) { Palette.paper }
        }
    }

    // Small: the latest friend moment as one full-bleed feed card, with the hour's count
    // in a white pill like Setlog's comment bubbles.
    private func small(_ state: GroupState) -> some View {
        let moment = state.latestFriendMoment(day: entry.day)
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        return ZStack {
            if let moment {
                // Bottom padding lifts the hour and caption clear of the pill and heart trail.
                MomentOverlay(moment: moment, name: state.name(of: moment.friendID), timeSize: 24)
                    .padding(.bottom, 18)
                    .id(moment.id)
                    .transition(.push(from: .bottom))
            }
            HStack(alignment: .bottom) {
                HStack(spacing: 3) {
                    Text("\(logged)/\(state.friends.count) in")
                        .contentTransition(.numericText(value: Double(logged)))
                    statusDoodles(logged: logged, size: 13)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.pill, in: Capsule())
                Spacer(minLength: 0)
                if let moment {
                    heartTrail(state: state, moment: moment, size: 22)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .containerBackground(for: .widget) {
            MomentImage(moment: moment, friend: moment.flatMap { state.friend($0.friendID) })
        }
    }

    // Medium: the two latest moments as tilted, stacked feed cards on Setlog's paper
    // background, with the hour's status beside them.
    private func medium(_ state: GroupState) -> some View {
        let recent = Array(state.todaysMoments(day: entry.day).filter { $0.friendID != state.meID }.prefix(2))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .contentTransition(.numericText(value: Double(logged)))
                    statusDoodles(logged: logged, size: 13)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(meLogged ? "Next in" : "Log in")
                        .font(.system(size: 11, weight: .semibold))
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
    }

    // Large: Setlog's feed, the three latest moments as staggered, tilted cards, with the
    // hour's status above and the countdown and nudge below. Sized for the Today View.
    private func large(_ state: GroupState) -> some View {
        let recent = Array(state.todaysMoments(day: entry.day).filter { $0.friendID != state.meID }.prefix(3))
        let logged = state.loggedCount(day: entry.day, hour: entry.hour)
        let meLogged = state.hasLogged(state.meID, day: entry.day, hour: entry.hour)
        let stagger: [(x: CGFloat, degrees: Double)] = [(-16, -2.5), (16, 2), (-10, -1.5)]

        return VStack(spacing: 10) {
            HStack(spacing: 3) {
                groupPill(state.name)
                Spacer(minLength: 8)
                Text("\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(state.friends.count) logged")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .contentTransition(.numericText(value: Double(logged)))
                statusDoodles(logged: logged, size: 14)
            }

            VStack(spacing: -6) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, moment in
                    card(state: state, moment: moment, size: CGSize(width: 250, height: 76),
                         timeSize: 17, trailSize: 14, interactive: true)
                        .rotationEffect(.degrees(stagger[index].degrees))
                        .offset(x: stagger[index].x)
                        .transition(.push(from: .top))
                }
            }
            .frame(maxHeight: .infinity)

            HourBar(state: state, day: entry.day, currentHour: entry.hour, height: 10, color: Palette.purple)

            HStack {
                hourAction(state: state)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(meLogged ? "Next in" : "Log in")
                        .font(.system(size: 11, weight: .semibold))
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

            Text("Today in \(today.count) logs")
                .font(.system(size: 20, weight: .black).width(.expanded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, moment in
                    Color.clear
                        .frame(height: 56)
                        .overlay(MomentImage(moment: moment, friend: state.friend(moment.friendID)))
                        .overlay {
                            Text(SetlogTime.clock(for: moment.hour))
                                .font(.system(size: 11, weight: .black).width(.expanded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.cardEdge, lineWidth: 2))
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2 : 2))
                }
            }

            HourBar(state: state, day: entry.day, height: 10, color: Palette.purple)

            Link(destination: DeepLink.vlog) {
                HStack(spacing: 4) {
                    Doodle(kind: .sparkle, size: 14)
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Watch today's vlog")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Palette.pill, in: Capsule())
                }
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
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    /// The group name in a white pill with a couple of sparkles, like a sticker on the page.
    private func groupPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Palette.pill, in: Capsule())
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
        if logged >= Self.busyHourCount {
            Doodle(kind: .flame, size: size)
        }
        if SetlogTime.isLateNight(entry.hour) {
            Doodle(kind: .moon, size: size)
        }
    }

    private static let busyHourCount = 3

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
                    .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Palette.pill, in: Capsule())
                }
            }
        } else if state.everyoneMissingNudged(now: entry.date) {
            HStack(spacing: 5) {
                Doodle(kind: .envelope, size: 16)
                Text("Nudged \(missing.count)")
                    .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Palette.pill, in: Capsule())
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
            Gauge(value: Double(logged), in: 0...Double(max(total, 1))) {
                Image(systemName: "camera.fill")
            } currentValueLabel: {
                Text("\(logged)/\(total)")
            }
            .gaugeStyle(.accessoryCircularCapacity)

        case .accessoryInline:
            if let latest = state.latestFriendMoment(day: entry.day) {
                Text("\(state.name(of: latest.friendID)) posted · \(logged)/\(total) in")
            } else {
                Text("\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(total) logged")
            }

        default:
            // Leads with who posted, like a notification you can glance at.
            VStack(alignment: .leading, spacing: 1) {
                if let latest = state.latestFriendMoment(day: entry.day) {
                    HStack(spacing: 3) {
                        Text("\(state.name(of: latest.friendID)) posted")
                            .font(.headline)
                            .widgetAccentable()
                        Text(latest.createdAt, style: .relative)
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text("Setlog · \(SetlogTime.clock(for: entry.hour))")
                        .font(.headline)
                        .widgetAccentable()
                }
                Text(meLogged
                     ? "\(SetlogTime.clock(for: entry.hour)) · you + \(max(logged - 1, 0)) logged"
                     : "\(SetlogTime.clock(for: entry.hour)) · \(logged)/\(total) logged")
                    .font(.caption)
                HStack(spacing: 3) {
                    Text(timerInterval: entry.hourStarts...entry.hourEnds, countsDown: true)
                        .monospacedDigit()
                    Text(meLogged ? "to next log" : "left to log")
                }
                .font(.caption)
            }
        }
    }
}
