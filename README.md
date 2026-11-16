# Setlog widgets (concept prototype)

A concept by Eric Hurchey. Not affiliated with or endorsed by newchat. The group, friends, and their posts are demo data, and the doodles are original drawings made in Setlog's spirit.

**The idea:** Setlog's habit is many short opens a day. In Korea, users open it 14 to 15 times a day for under a minute each. Every one of those opens could start from the Home Screen, Today View, or Lock Screen. These widgets turn the hourly prompt into something your friends' activity pulls you into: you see who just posted, how many of the group logged this hour, and how long you have left, and you can react or nudge friends without opening the app.

## What's in it

**Home Screen widget**
- **Small:** your friends' latest moment as a full-bleed Setlog card: name, the hour on a 24-hour clock ("17:00"), their caption, and a trail of reactions. A pill shows how many logged this hour.
- **Medium:** the two latest moments as tilted, stacked cards. Beside them: the group, the hour's count, a countdown, today's 24-hour bar, and a **Nudge** button showing who hasn't logged.

**Today View widget** (swipe right from the Lock Screen or Home Screen)
- **Large:** Setlog's feed, the three latest moments as staggered cards, with every card's reaction button live.
- **End-of-day recap:** from 22:00 the large widget turns into a scrapbook of the day's moments, "Today in 14 logs", with **Watch today's vlog**. It's Setlog's "keep your day as a vlog" at a glance.

**Lock Screen widgets**
- **Rectangular:** "Mina posted · 2 min", the hour's count, and a live countdown.
- **Circular:** a ring filling up as friends log ("3/5").
- **Inline** (above the clock): "Mina posted · 3/5 in".

**Works without opening anything**
- Tap a card's corner to add your ❤️ to its reaction trail. Friends react in their own emoji (👀, 🐶, ❤️, 😂).
- Tap **Nudge** to nudge everyone who hasn't logged this hour.
- When everyone else is in, the button becomes **Log 17:00**, which opens straight to Setlog's camera in production.

**Design details**
- Setlog's look: warm paper background, white-bordered photo cards, the hour in a wide heavy face, white pills, and their purple, pink, and flame colors.
- Original hand-drawn doodles that react to the hour: sparkles on the group name, an envelope on Nudge, flames once 3 or more have logged, a smiling star when it's your turn, and a moon late at night.
- Animations: counts roll and new posts slide onto the stack when a friend posts.
- Dark mode with a warm charcoal palette, and tinted Home Screens (photos turn grayscale instead of a flat tint).
- Korean throughout, including the demo group (룸메들) and captions like "스낵타임 굿 🍪". The translations are drafts for a native speaker to check.

**Placeholder app**
iOS only ships widgets inside an app. In production that app is Setlog itself, so here it's a single screen that never appears in the demo. It has two off-camera buttons: **Restart demo** and **Preview tonight's recap**.

## What's real and what's mocked

| Part | Status |
|---|---|
| Home Screen, Today View, and Lock Screen widgets | Real (WidgetKit) |
| Reaction and Nudge buttons on the widget | Real (App Intents); nudges are recorded, not sent |
| Animations, dark mode, tinted mode, Korean | Real |
| Friends and their posts | Mocked: the widget schedules each friend who hasn't logged to post 30 seconds apart, standing in for the backend |
| Photos | Mocked: soft color washes stand in for still frames from 2-second clips |
| Log button and "Watch today's vlog" | Open the placeholder app; in production they open Setlog's camera and the day's vlog |

## Run it

Requirements: a Mac with Xcode and an iOS Simulator runtime. Deployment target iOS 17.0.

1. Install XcodeGen: `brew install xcodegen`.
2. Generate the project: `xcodegen generate` (reads `project.yml`, writes `SetlogConcept.xcodeproj`).
3. Open `SetlogConcept.xcodeproj`, pick an iPhone Simulator, and run the **SetlogConcept** scheme.

The App Group (`group.com.example.setlogconcept`) works as-is in the Simulator. To run on a device, change it in `project.yml` and `Shared/Store.swift` (`appGroupID`) to one registered to your team, and set your team under Signing & Capabilities.

## Demo flow

1. Run the app and tap **Restart demo** before each take.
2. Add the widgets. **Home Screen:** long-press, Edit, Add Widget, Setlog Concept, then add the small and medium sizes. **Today View:** swipe right, Edit, and add the large size. **Lock Screen:** long-press the Lock Screen, Customize, and add the **This hour** widgets.
3. Watch friends post. Mina has already logged. Jae, Sora, and Alex follow every 30 seconds, the stack updates, flames appear at 3/5, and the star and **Log** button appear once everyone else is in.
4. Tap a card's ❤️ and tap **Nudge**.
5. For the recap, tap **Preview tonight's recap** in the app (or wait until 22:00).
6. For Korean, set the device language to Korean, then tap **Restart demo** so the demo group is created in Korean.

## Talking points for production

- **Live updates:** a silent push reloads the widgets when a friend posts, so the stack and "Mina posted · 2 min" are always current.
- **Nudges** become pushes to the friends who haven't logged, rate-limited so they feel friendly.
- **The recap** becomes a shareable vlog of the day's clips, stitched on the server.
- **The metric it moves:** opens per day, and the share of opens that start from the Home Screen, Today View, and Lock Screen.
