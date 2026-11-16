import Foundation
import ImageIO
import UIKit

// Shared by the app and the widget extension. Add this file to BOTH targets.

/// Reads and writes the group through an App Group container, so every widget
/// and widget button sees the same data.
enum Store {
    /// Change this to your own App Group ID, and add the same ID to BOTH targets
    /// under Signing & Capabilities > App Groups.
    static let appGroupID = "group.com.example.setlogconcept"

    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var root: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SetlogConcept", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var stateFile: URL { root.appendingPathComponent("group.json") }

    static var imagesFolder: URL {
        let url = root.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Group

    static func load() -> GroupState? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(GroupState.self, from: data)
    }

    static func save(_ state: GroupState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }

    /// Seconds between scripted friend posts.
    static let demoPostInterval: TimeInterval = 30

    /// The Home Screen and Lock Screen widgets can reload at the same moment.
    private static let lock = NSLock()

    /// Loads the group as of `now`: creates the demo group the first time, releases scripted
    /// posts that are due, and schedules this hour's scripted posts.
    static func loadCurrent(now: Date = Date()) -> GroupState {
        lock.lock()
        defer { lock.unlock() }
        var state = load() ?? seed(now: now)
        state.dropOldMoments(now: now)
        state.releaseDuePosts(now: now)
        scheduleDemoPosts(&state, now: now)
        save(state)
        return state
    }

    /// Stands in for the backend: each friend who hasn't logged this hour posts in turn,
    /// `demoPostInterval` seconds apart, so the widgets visibly update during a demo.
    private static func scheduleDemoPosts(_ state: inout GroupState, now: Date) {
        let hourStart = SetlogTime.startOfHour(for: now)
        guard state.scriptedHour != hourStart else { return }
        state.scriptedHour = hourStart

        let alreadyScheduled = Set(state.pending.map(\.friendID))
        let missing = state.missing(day: SetlogTime.day(for: now), hour: SetlogTime.hour(for: now))
            .filter { !alreadyScheduled.contains($0.id) }
        for (index, friend) in missing.enumerated() {
            let postAt = now.addingTimeInterval(demoPostInterval * Double(index + 1))
            state.pending.append(demoMoment(by: friend, at: postAt))
        }
    }

    /// A demo post with a photo (or a stand-in wash), a caption, and a reaction or two from friends.
    private static func demoMoment(by friend: Friend, at date: Date) -> Moment {
        let hour = SetlogTime.hour(for: date)
        let friendIndex = DemoData.friends.firstIndex { $0.id == friend.id } ?? 0
        let frame = DemoPhotos.image(at: friendIndex * 5 + hour) ?? Card.image(hue: friend.hue, variation: hour)
        let file = saveImage(frame) ?? ""
        return Moment(friendID: friend.id, day: SetlogTime.day(for: date), hour: hour, createdAt: date,
                      imageFile: file,
                      caption: DemoData.caption(for: friend.id, hour: hour),
                      reactions: DemoData.reactors(for: friend.id, hour: hour))
    }

    /// A demo group with a few friends who logged over the last few hours,
    /// including one who already logged this hour.
    static func seed(now: Date = Date()) -> GroupState {
        var state = GroupState(name: DemoData.groupName, meID: "me", friends: DemoData.friends, moments: [])
        let currentHour = SetlogTime.hour(for: now)
        let others = state.others

        for hour in max(0, currentHour - 3)..<currentHour {
            for (index, friend) in others.enumerated() where (hour + index) % 3 != 0 {
                let created = Calendar.current.date(bySettingHour: hour, minute: 5 + index * 9, second: 0, of: now) ?? now
                state.moments.append(demoMoment(by: friend, at: created))
            }
        }
        for (index, friend) in others.prefix(1).enumerated() {
            let created = max(SetlogTime.startOfHour(for: now), now.addingTimeInterval(Double(-90 * (index + 1))))
            state.moments.append(demoMoment(by: friend, at: created))
        }
        return state
    }

    static func reset() {
        try? FileManager.default.removeItem(at: stateFile)
        try? FileManager.default.removeItem(at: imagesFolder)
    }

    // MARK: Images

    /// Saves a small JPEG (widgets have tight memory limits) and returns its file name.
    static func saveImage(_ image: UIImage) -> String? {
        let width: CGFloat = 400
        let height = width * image.size.height / max(image.size.width, 1)
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.75) else { return nil }
        let file = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imagesFolder.appendingPathComponent(file), options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    static func image(named file: String) -> UIImage? {
        guard !file.isEmpty else { return nil }
        return UIImage(contentsOfFile: imagesFolder.appendingPathComponent(file).path)
    }
}

/// Photos dropped into the DemoPhotos folder, used as friends' still frames in the demo.
enum DemoPhotos {
    private static let urls: [URL] = (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "DemoPhotos") ?? [])
        .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    /// Downsampled while decoding: a full-size phone photo would blow the widget's memory limit.
    static func image(at index: Int) -> UIImage? {
        guard !urls.isEmpty, let source = CGImageSourceCreateWithURL(urls[index % urls.count] as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Stand-in frames for demo friends' posts: a soft, out-of-focus wash of color in the
/// friend's hue. The widget draws the hour and caption on top, like Setlog's feed cards.
enum Card {
    static func image(hue: Double, variation: Int, size: CGSize = CGSize(width: 400, height: 500)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(hue: wrap(hue), saturation: 0.38, brightness: 0.60, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let spots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
                (0.20, 0.20, 0.70), (0.85, 0.30, 0.55), (0.30, 0.85, 0.60), (0.80, 0.85, 0.50), (0.55, 0.50, 0.45),
            ]
            for index in spots.indices {
                let spot = spots[(index + variation) % spots.count]
                let center = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
                let color = UIColor(hue: wrap(hue + Double(index - 2) * 0.03),
                                    saturation: 0.32 + 0.08 * CGFloat(index % 3),
                                    brightness: 0.66 + 0.08 * CGFloat(index % 4), alpha: 0.85)
                let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { continue }
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: spot.radius * size.width, options: [])
            }
        }
    }

    private static func wrap(_ hue: Double) -> CGFloat {
        let value = hue.truncatingRemainder(dividingBy: 1)
        return CGFloat(value < 0 ? value + 1 : value)
    }
}
