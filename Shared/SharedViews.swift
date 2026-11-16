import SwiftUI
import UIKit
import WidgetKit

// Shared by the app and the widget extension. Add this file to BOTH targets.

/// Setlog's brand palette: warm paper background, near-black ink, soft purple and pink accents.
/// Surface colors follow light and dark mode; accent colors stay the same in both.
enum Palette {
    static let paper = Color(light: 0xF3EFEB, dark: 0x1D1A18)
    static let ink = Color(light: 0x111111, dark: 0xF3EFEB)
    static let muted = Color(light: 0x9B9B9B, dark: 0x8C857F)
    /// White pills by day, warm charcoal ones at night.
    static let pill = Color(light: 0xFFFFFF, dark: 0x2E2A27)
    /// The border around feed cards; softer at night so photos don't glare.
    static let cardEdge = Color(light: 0xFFFFFF, dark: 0x45403C)
    /// Doodle outlines stay black in both modes, like stickers.
    static let outline = Color(hex: 0x111111)
    static let purple = Color(hex: 0xB888FF)
    static let pink = Color(hex: 0xFFC8C8)
    static let heart = Color(hex: 0xFF5840)
    static let flame = Color(hex: 0xFF8058)
    static let butter = Color(hex: 0xFFE9A0)
    static let moon = Color(hex: 0xFFF6DA)
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 24 thin bars, one per hour, brighter when more of the group logged that hour.
struct HourBar: View {
    let state: GroupState
    let day: String
    var currentHour: Int?
    var height: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { hour in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(opacity(hour)))
                    .frame(height: hour == currentHour ? height : height * 0.7)
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func opacity(_ hour: Int) -> Double {
        let count = state.loggedCount(day: day, hour: hour)
        guard count > 0 else { return 0.15 }
        return 0.35 + 0.65 * Double(count) / Double(max(state.friends.count, 1))
    }
}

/// A moment's still frame, or a soft wash of the friend's color if there's no image.
struct MomentImage: View {
    let moment: Moment?
    let friend: Friend?

    var body: some View {
        if let moment, let image = Store.image(named: moment.imageFile) {
            if #available(iOS 18.0, *) {
                // On a tinted Home Screen, show photos in grayscale rather than a flat tint.
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            let hue = friend?.hue ?? 0.6
            LinearGradient(colors: [Color(hue: hue, saturation: 0.25, brightness: 0.75),
                                    Color(hue: hue, saturation: 0.35, brightness: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// The text Setlog lays over each feed card: the poster's name top-left, and the hour
/// in a wide, heavy face with the caption underneath, centered.
struct MomentOverlay: View {
    let moment: Moment
    let name: String
    /// Point size of the hour; the name and caption scale from it.
    var timeSize: CGFloat = 22

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(SetlogTime.clock(for: moment.hour))
                    .font(.system(size: timeSize, weight: .black).width(.expanded))
                if !moment.caption.isEmpty {
                    Text(moment.caption)
                        .font(.system(size: timeSize * 0.48, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(name)
                .font(.system(size: timeSize * 0.52, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// Reactions trailing down a card's corner, growing toward the bottom like Setlog's.
/// Friends' reactions come first, each in their own emoji. The last spot is mine:
/// a filled heart once I've reacted, an empty one to tap until then.
struct ReactionTrail: View {
    /// Friends' reaction emoji, oldest first.
    let others: [String]
    let mine: Bool
    var size: CGFloat = 20

    var body: some View {
        let shown = Array(others.suffix(2))
        VStack(alignment: .trailing, spacing: -size * 0.12) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, emoji in
                Text(emoji)
                    .font(.system(size: size * (0.38 + 0.12 * CGFloat(index))))
                    .offset(x: index % 2 == 0 ? -size * 0.45 : -size * 0.1)
            }
            if mine {
                Text("❤️").font(.system(size: size * 0.8))
            } else {
                Image(systemName: "heart")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 1.1, height: size * 1.1)
                    .background(.black.opacity(0.25), in: Circle())
            }
        }
    }
}

/// Small round avatar with the friend's initial.
struct Avatar: View {
    let friend: Friend
    var size: CGFloat = 22
    var dimmed = false

    var body: some View {
        Text(friend.initial)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hue: friend.hue, saturation: 0.5, brightness: 0.65), in: Circle())
            .opacity(dimmed ? 0.35 : 1)
    }
}

/// Small label so nobody mistakes the prototype for the real app.
struct ConceptTag: View {
    var body: some View {
        Text("Concept prototype · demo friends")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
