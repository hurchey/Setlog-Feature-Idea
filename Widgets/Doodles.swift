import SwiftUI

/// Small hand-drawn stickers in the spirit of Setlog's branding: thick ink outlines with a
/// slight wobble and one soft fill. These are original drawings, not copies of newchat's artwork.
struct Doodle: View {
    enum Kind {
        case sparkle, flame, star, envelope, moon
    }

    let kind: Kind
    var size: CGFloat = 20

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
                    .stroke(Palette.outline, style: featureLine)
            }
        case .envelope:
            ZStack {
                inked(EnvelopeShape(), fill: .white)
                EnvelopeFlapShape().stroke(Palette.outline, style: outline)
                inked(HeartShape(), fill: Palette.heart)
            }
            .rotationEffect(.degrees(-8))
        case .moon:
            ZStack {
                inked(MoonShape(), fill: Palette.moon)
                FaceShape(eyes: [CGPoint(x: 0.24, y: 0.52)], mouth: CGPoint(x: 0.34, y: 0.68))
                    .stroke(Palette.outline, style: featureLine)
            }
            .rotationEffect(.degrees(-12))
        }
    }

    private var outline: StrokeStyle {
        StrokeStyle(lineWidth: max(1.1, size * 0.065), lineCap: .round, lineJoin: .round)
    }

    /// Eyes and mouths read better a touch thinner than the outline.
    private var featureLine: StrokeStyle {
        StrokeStyle(lineWidth: max(0.9, size * 0.05), lineCap: .round, lineJoin: .round)
    }

    private func inked<S: Shape>(_ shape: S, fill: Color) -> some View {
        shape
            .fill(fill)
            .overlay(shape.stroke(Palette.outline, style: outline))
    }
}

// MARK: - Pen

/// Plots unit-square coordinates into a rect with a small, repeatable jitter so strokes look
/// drawn by hand rather than ruled. The same seed always gives the same wobble.
private struct Pen {
    private let rect: CGRect
    private let seed: Double
    private var count = 0.0
    private(set) var path = Path()

    init(_ rect: CGRect, seed: Double) {
        self.rect = rect
        self.seed = seed
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
        count += 1
        let amount = 0.02 * min(rect.width, rect.height)
        return CGPoint(x: rect.minX + x * rect.width + noise(count) * amount,
                       y: rect.minY + y * rect.height + noise(count + 0.37) * amount)
    }

    /// A repeatable value in -1...1.
    private func noise(_ n: Double) -> CGFloat {
        let value = sin((seed + n) * 12.9898) * 43758.5453
        return CGFloat(value - value.rounded(.down)) * 2 - 1
    }
}

// MARK: - Shapes

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

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect, seed: 8)
        pen.move(0.5, 0.74)
        pen.curve(0.35, 0.53, 0.42, 0.68, 0.35, 0.62)
        pen.curve(0.5, 0.49, 0.35, 0.43, 0.46, 0.41)
        pen.curve(0.65, 0.53, 0.54, 0.41, 0.65, 0.43)
        pen.curve(0.5, 0.74, 0.65, 0.62, 0.58, 0.68)
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
