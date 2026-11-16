import SwiftUI

/// Small hand-drawn stickers in the spirit of Setlog's branding: thick ink outlines with a
/// slight wobble and one soft fill. These are original drawings, not copies of newchat's artwork.
struct Doodle: View {
    enum Kind {
        case sparkle, flame, star, envelope, moon, heart, puppy
    }

    let kind: Kind
    var size: CGFloat = 20
    /// Outlines only, in the primary color. The Lock Screen draws widgets in a single tint,
    /// where fills would turn into solid blobs.
    var lineArt = false

    var body: some View {
        content
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .sparkle:
            inked(SparkleShape(), fill: .white)
        case .flame:
            ZStack {
                inked(FlameShape(), fill: Palette.flame)
                inked(FlameCoreShape(), fill: Palette.butter)
            }
        case .star:
            ZStack {
                inked(StarShape(), fill: Palette.butter)
                FaceShape(eyes: [CGPoint(x: 0.42, y: 0.52), CGPoint(x: 0.58, y: 0.52)], mouth: CGPoint(x: 0.5, y: 0.63))
                    .stroke(ink, style: featureLine)
            }
        case .envelope:
            ZStack {
                inked(EnvelopeShape(), fill: .white)
                EnvelopeFlapShape().stroke(ink, style: outline)
                inked(HeartShape(frame: CGRect(x: 0.35, y: 0.41, width: 0.30, height: 0.33)), fill: Palette.heart)
            }
            .rotationEffect(.degrees(-8))
        case .moon:
            ZStack {
                inked(MoonShape(), fill: Palette.moon)
                FaceShape(eyes: [CGPoint(x: 0.24, y: 0.52)], mouth: CGPoint(x: 0.34, y: 0.68))
                    .stroke(ink, style: featureLine)
            }
            .rotationEffect(.degrees(-12))
        case .heart:
            inked(HeartShape(frame: CGRect(x: 0.06, y: 0.1, width: 0.88, height: 0.8)), fill: Palette.heart)
                .rotationEffect(.degrees(-10))
        case .puppy:
            ZStack {
                inked(PuppyEarsShape(), fill: Palette.ear)
                inked(PuppyHeadShape(), fill: .white)
                PuppyFeaturesShape().fill(ink)
                PuppyMouthShape().stroke(ink, style: featureLine)
            }
        }
    }

    private var ink: Color {
        lineArt ? .primary : Palette.outline
    }

    private var outline: StrokeStyle {
        StrokeStyle(lineWidth: max(1.1, size * 0.065), lineCap: .round, lineJoin: .round)
    }

    /// Eyes and mouths read better a touch thinner than the outline.
    private var featureLine: StrokeStyle {
        StrokeStyle(lineWidth: max(0.9, size * 0.05), lineCap: .round, lineJoin: .round)
    }

    @ViewBuilder
    private func inked<S: Shape>(_ shape: S, fill: Color) -> some View {
        if lineArt {
            shape.stroke(ink, style: outline)
        } else {
            shape
                .fill(fill)
                .overlay(shape.stroke(ink, style: outline))
        }
    }
}

/// Setlog's paper covered in faint pencil doodles, with a hand-drawn pink frame around the edge.
/// Content sits on top.
struct DoodlePaper: View {
    private struct Mark {
        let kind: Doodle.Kind
        /// Center, as a fraction of the widget's width and height.
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let degrees: Double
    }

    private static let marks: [Mark] = [
        Mark(kind: .star, x: 0.05, y: 0.14, size: 18, degrees: -12),
        Mark(kind: .heart, x: 0.37, y: 0.07, size: 14, degrees: 10),
        Mark(kind: .sparkle, x: 0.70, y: 0.09, size: 11, degrees: 0),
        Mark(kind: .flame, x: 0.94, y: 0.30, size: 16, degrees: 8),
        Mark(kind: .envelope, x: 0.07, y: 0.56, size: 16, degrees: -10),
        Mark(kind: .star, x: 0.31, y: 0.36, size: 12, degrees: 14),
        Mark(kind: .sparkle, x: 0.49, y: 0.50, size: 9, degrees: 0),
        Mark(kind: .heart, x: 0.79, y: 0.56, size: 12, degrees: -14),
        Mark(kind: .sparkle, x: 0.22, y: 0.90, size: 12, degrees: 0),
        Mark(kind: .moon, x: 0.55, y: 0.93, size: 16, degrees: -8),
        Mark(kind: .sparkle, x: 0.63, y: 0.71, size: 10, degrees: 0),
        Mark(kind: .puppy, x: 0.92, y: 0.82, size: 18, degrees: -6),
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.paper
                ZStack {
                    ForEach(Self.marks.indices, id: \.self) { index in
                        let mark = Self.marks[index]
                        Doodle(kind: mark.kind, size: mark.size)
                            .rotationEffect(.degrees(mark.degrees))
                            .position(x: mark.x * geometry.size.width, y: mark.y * geometry.size.height)
                    }
                }
                .compositingGroup()
                .grayscale(1)
                .opacity(0.16)
                SketchRoundedRect(cornerRadius: 20, wobble: 1.4, seed: 3)
                    .stroke(Palette.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(6)
            }
        }
    }
}

extension View {
    /// A pill with a hand-inked edge, like a sticker label.
    func sketchPill() -> some View {
        background(Palette.pill, in: Capsule())
            .overlay(SketchRoundedRect(wobble: 0.8, seed: 5).stroke(Palette.ink, lineWidth: 1.2))
    }
}

// MARK: - Wobble

/// Nudges points by a small, repeatable amount so lines look drawn by hand rather than ruled.
/// The same seed always gives the same wobble, so outlines don't shimmer between renders.
private struct Wobble {
    private let seed: Double
    private let amount: CGFloat
    private var count = 0.0

    init(seed: Double, amount: CGFloat) {
        self.seed = seed
        self.amount = amount
    }

    mutating func nudge(_ point: CGPoint) -> CGPoint {
        count += 1
        return CGPoint(x: point.x + noise(count) * amount, y: point.y + noise(count + 0.37) * amount)
    }

    /// A repeatable value in -1...1.
    private func noise(_ n: Double) -> CGFloat {
        let value = sin((seed + n) * 12.9898) * 43758.5453
        return CGFloat(value - value.rounded(.down)) * 2 - 1
    }
}

// MARK: - Pen

/// Plots unit-square coordinates into a rect, wobbling each point a little.
private struct Pen {
    private let rect: CGRect
    private var wobble: Wobble
    private(set) var path = Path()

    init(_ rect: CGRect, seed: Double) {
        self.rect = rect
        wobble = Wobble(seed: seed, amount: 0.02 * min(rect.width, rect.height))
    }

    mutating func move(_ x: CGFloat, _ y: CGFloat) {
        path.move(to: point(x, y))
    }

    mutating func line(_ x: CGFloat, _ y: CGFloat) {
        path.addLine(to: point(x, y))
    }

    mutating func quad(_ x: CGFloat, _ y: CGFloat, control cx: CGFloat, _ cy: CGFloat) {
        path.addQuadCurve(to: point(x, y), control: point(cx, cy))
    }

    mutating func curve(_ x: CGFloat, _ y: CGFloat,
                        _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
        path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
    }

    mutating func close() {
        path.closeSubpath()
    }

    private mutating func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        wobble.nudge(CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
    }
}

// MARK: - Hand-drawn outlines

/// A rounded rectangle drawn freehand: edges bow slightly, and the line runs a little past
/// where it started, the way a pen does. Leave `cornerRadius` nil for a capsule.
struct SketchRoundedRect: Shape {
    var cornerRadius: CGFloat?
    var wobble: CGFloat
    var seed: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius ?? .infinity, min(rect.width, rect.height) / 2)
        let overshoot = min(12, rect.width * 0.12)
        var jitter = Wobble(seed: seed, amount: wobble)
        var path = Path()

        func edge(to end: CGPoint) {
            let start = path.currentPoint ?? end
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            path.addQuadCurve(to: jitter.nudge(end), control: jitter.nudge(middle))
        }

        func corner(to end: CGPoint, control: CGPoint) {
            path.addQuadCurve(to: jitter.nudge(end), control: control)
        }

        path.move(to: jitter.nudge(CGPoint(x: rect.minX + radius, y: rect.minY)))
        edge(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        corner(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        edge(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        corner(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        edge(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        corner(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        edge(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        corner(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        edge(to: CGPoint(x: rect.minX + radius + overshoot, y: rect.minY))
        return path
    }
}

/// A loopy freehand line, for underlining.
struct SquiggleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 9)
        pen.move(0.01, 0.6)
        pen.curve(0.26, 0.5, 0.08, 0.1, 0.18, 0.95)
        pen.curve(0.51, 0.5, 0.33, 0.05, 0.43, 0.95)
        pen.curve(0.76, 0.5, 0.58, 0.05, 0.68, 0.95)
        pen.curve(0.99, 0.4, 0.83, 0.05, 0.93, 0.7)
        return pen.path
    }
}

// MARK: - Sticker shapes

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 1)
        pen.move(0.5, 0.04)
        pen.quad(0.96, 0.5, control: 0.58, 0.42)
        pen.quad(0.5, 0.96, control: 0.58, 0.58)
        pen.quad(0.04, 0.5, control: 0.42, 0.58)
        pen.quad(0.5, 0.04, control: 0.42, 0.42)
        pen.close()
        return pen.path
    }
}

private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 2)
        pen.move(0.5, 0.96)
        pen.curve(0.14, 0.64, 0.28, 0.96, 0.12, 0.82)
        pen.curve(0.40, 0.20, 0.16, 0.44, 0.32, 0.36)
        pen.curve(0.56, 0.04, 0.46, 0.10, 0.52, 0.08)
        pen.curve(0.68, 0.40, 0.60, 0.18, 0.64, 0.30)
        pen.curve(0.80, 0.28, 0.72, 0.36, 0.76, 0.30)
        pen.curve(0.87, 0.64, 0.88, 0.40, 0.90, 0.52)
        pen.curve(0.5, 0.96, 0.85, 0.84, 0.72, 0.96)
        pen.close()
        return pen.path
    }
}

private struct FlameCoreShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 3)
        pen.move(0.5, 0.86)
        pen.curve(0.36, 0.70, 0.40, 0.86, 0.34, 0.78)
        pen.curve(0.52, 0.48, 0.38, 0.60, 0.48, 0.54)
        pen.curve(0.64, 0.72, 0.58, 0.56, 0.66, 0.64)
        pen.curve(0.5, 0.86, 0.62, 0.80, 0.56, 0.86)
        pen.close()
        return pen.path
    }
}

private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 4)
        for index in 0..<10 {
            let radius: CGFloat = index.isMultiple(of: 2) ? 0.47 : 0.24
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let x = 0.5 + cos(angle) * radius
            let y = 0.54 + sin(angle) * radius
            if index == 0 {
                pen.move(x, y)
            } else {
                pen.line(x, y)
            }
        }
        pen.close()
        return pen.path
    }
}

/// Happy closed eyes and a small smile, placed in unit coordinates.
private struct FaceShape: Shape {
    let eyes: [CGPoint]
    let mouth: CGPoint

    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 5)
        for eye in eyes {
            pen.move(eye.x - 0.05, eye.y)
            pen.quad(eye.x + 0.05, eye.y, control: eye.x, eye.y - 0.07)
        }
        pen.move(mouth.x - 0.06, mouth.y)
        pen.quad(mouth.x + 0.06, mouth.y, control: mouth.x, mouth.y + 0.07)
        return pen.path
    }
}

private struct EnvelopeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 6)
        pen.move(0.08, 0.24)
        pen.line(0.92, 0.22)
        pen.line(0.93, 0.80)
        pen.line(0.07, 0.82)
        pen.close()
        return pen.path
    }
}

private struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 7)
        pen.move(0.09, 0.26)
        pen.line(0.5, 0.56)
        pen.line(0.91, 0.24)
        return pen.path
    }
}

/// A heart drawn inside `frame`, given in unit coordinates of the doodle.
private struct HeartShape: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        let inner = CGRect(x: rect.minX + frame.minX * rect.width, y: rect.minY + frame.minY * rect.height,
                           width: frame.width * rect.width, height: frame.height * rect.height)
        var pen = Pen(inner, seed: 8)
        pen.move(0.5, 1.0)
        pen.curve(0, 0.36, 0.23, 0.82, 0, 0.64)
        pen.curve(0.5, 0.24, 0, 0.06, 0.37, 0)
        pen.curve(1, 0.36, 0.63, 0, 1, 0.06)
        pen.curve(0.5, 1.0, 1, 0.64, 0.77, 0.82)
        pen.close()
        return pen.path
    }
}

/// A crescent: a circle with a bite taken out of its upper right.
private struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let full = Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.06,
                                          width: rect.width * 0.88, height: rect.height * 0.88))
        let bite = Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.38, y: rect.minY - rect.height * 0.02,
                                          width: rect.width * 0.72, height: rect.height * 0.72))
        return full.subtracting(bite)
    }
}

private struct PuppyEarsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 12)
        pen.move(0.32, 0.28)
        pen.curve(0.08, 0.64, 0.16, 0.24, 0.04, 0.46)
        pen.curve(0.30, 0.60, 0.12, 0.78, 0.26, 0.74)
        pen.close()
        pen.move(0.68, 0.28)
        pen.curve(0.92, 0.64, 0.84, 0.24, 0.96, 0.46)
        pen.curve(0.70, 0.60, 0.88, 0.78, 0.74, 0.74)
        pen.close()
        return pen.path
    }
}

private struct PuppyHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 13)
        pen.move(0.5, 0.20)
        pen.curve(0.80, 0.55, 0.70, 0.20, 0.82, 0.36)
        pen.curve(0.5, 0.88, 0.78, 0.78, 0.64, 0.88)
        pen.curve(0.20, 0.55, 0.36, 0.88, 0.22, 0.78)
        pen.curve(0.5, 0.20, 0.18, 0.36, 0.30, 0.20)
        pen.close()
        return pen.path
    }
}

/// Eyes and nose, filled.
private struct PuppyFeaturesShape: Shape {
    func path(in rect: CGRect) -> Path {
        func dot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + (x - w / 2) * rect.width, y: rect.minY + (y - h / 2) * rect.height,
                   width: w * rect.width, height: h * rect.height)
        }
        var path = Path()
        path.addEllipse(in: dot(0.40, 0.50, 0.07, 0.08))
        path.addEllipse(in: dot(0.60, 0.50, 0.07, 0.08))
        path.addEllipse(in: dot(0.50, 0.63, 0.12, 0.08))
        return path
    }
}

private struct PuppyMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 14)
        pen.move(0.42, 0.71)
        pen.quad(0.5, 0.70, control: 0.46, 0.77)
        pen.quad(0.58, 0.71, control: 0.54, 0.77)
        return pen.path
    }
}
