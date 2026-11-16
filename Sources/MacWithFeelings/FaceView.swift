import FeelingsCore
import SwiftUI

extension Mood {
    /// The colour of the laptop's screen in this mood.
    var screen: Color {
        switch self {
        case .happy: Color(red: 0.56, green: 0.89, blue: 0.71)
        case .content: Color(red: 0.66, green: 0.85, blue: 0.96)
        case .overheated: Color(red: 1.00, green: 0.60, blue: 0.46)
        case .starving: Color(red: 0.97, green: 0.83, blue: 0.53)
        case .overwhelmed: Color(red: 0.79, green: 0.65, blue: 0.96)
        case .bloated: Color(red: 0.74, green: 0.86, blue: 0.55)
        case .sleepy: Color(red: 0.49, green: 0.55, blue: 0.84)
        case .worried: Color(red: 0.96, green: 0.72, blue: 0.81)
        case .cramped: Color(red: 0.95, green: 0.76, blue: 0.61)
        }
    }
}

/// A little laptop whose screen is its face. Blinks, sweats, snores and talks.
struct FaceView: View {
    var mood: Mood
    var mouthOpen = false
    /// Off for the icon render, so it is a still image.
    var animated = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: 0)
        }
    }

    private func canvas(time t: Double) -> some View {
        Canvas { ctx, size in
            // Draw in a 100 × 80 space, scaled to fit.
            let scale = min(size.width / 100, size.height / 80)
            ctx.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 80 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            draw(&ctx, t: t)
        }
    }

    private let ink = Color(red: 0.11, green: 0.12, blue: 0.14)

    private func draw(_ ctx: inout GraphicsContext, t: Double) {
        // Gentle bob, faster when upset.
        let bob = animated ? sin(t * (mood.isUpset ? 3.2 : 1.6)) * 0.8 : 0
        var c = ctx
        c.translateBy(x: 0, y: bob)

        // Lid and screen.
        let lid = Path(roundedRect: CGRect(x: 12, y: 4, width: 76, height: 58), cornerRadius: 7)
        c.fill(lid, with: .color(ink))
        let screenRect = CGRect(x: 16, y: 8, width: 68, height: 50)
        c.fill(Path(roundedRect: screenRect, cornerRadius: 4), with: .linearGradient(
            Gradient(colors: [mood.screen.opacity(0.85), mood.screen]),
            startPoint: CGPoint(x: 50, y: 8), endPoint: CGPoint(x: 50, y: 58)
        ))
        // Base with a trackpad notch.
        var base = Path()
        base.move(to: CGPoint(x: 6, y: 63))
        base.addLine(to: CGPoint(x: 94, y: 63))
        base.addQuadCurve(to: CGPoint(x: 90, y: 70), control: CGPoint(x: 96, y: 70))
        base.addLine(to: CGPoint(x: 10, y: 70))
        base.addQuadCurve(to: CGPoint(x: 6, y: 63), control: CGPoint(x: 4, y: 70))
        c.fill(base, with: .color(Color(red: 0.78, green: 0.80, blue: 0.84)))
        c.fill(Path(roundedRect: CGRect(x: 42, y: 63, width: 16, height: 2.2), cornerRadius: 1),
               with: .color(Color(red: 0.62, green: 0.64, blue: 0.69)))

        // Blink for 0.15 s every ~4 s.
        let blinking = animated && (t.truncatingRemainder(dividingBy: 4.3)) < 0.15
        drawEyes(&c, blinking: blinking, t: t)
        drawMouth(&c, t: t)
        drawExtras(&c, t: t)
    }

    private func stroke(_ c: inout GraphicsContext, _ p: Path, width: CGFloat = 2.6) {
        c.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drawEyes(_ c: inout GraphicsContext, blinking: Bool, t: Double) {
        for x in [38.0, 62.0] {
            let y = 28.0
            if blinking && mood != .sleepy {
                stroke(&c, Path { $0.move(to: CGPoint(x: x - 4, y: y)); $0.addLine(to: CGPoint(x: x + 4, y: y)) })
                continue
            }
            switch mood {
            case .happy:
                stroke(&c, Path { $0.addArc(center: CGPoint(x: x, y: y + 2), radius: 4.5,
                                            startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false) })
            case .sleepy:
                stroke(&c, Path { $0.addArc(center: CGPoint(x: x, y: y - 1), radius: 4.5,
                                            startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false) })
            case .overheated, .cramped:
                // > <
                let dir: Double = x < 50 ? 1 : -1
                stroke(&c, Path {
                    $0.move(to: CGPoint(x: x - 4 * dir, y: y - 4))
                    $0.addLine(to: CGPoint(x: x + 3 * dir, y: y))
                    $0.addLine(to: CGPoint(x: x - 4 * dir, y: y + 4))
                })
            case .bloated:
                // Swirly eyes.
                var p = Path()
                let spin = animated ? t * 4 : 0
                for i in 0...36 {
                    let a = Double(i) / 36 * 4 * .pi + spin * (x < 50 ? 1 : -1)
                    let r = 0.5 + Double(i) / 36 * 4.5
                    let pt = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                stroke(&c, p, width: 1.8)
            case .overwhelmed:
                // Wide eyes, tiny darting pupils.
                c.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)), with: .color(.white))
                c.stroke(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)), with: .color(ink), lineWidth: 1.6)
                let dart = animated ? sin(t * 7) * 2.2 : 0
                c.fill(Path(ellipseIn: CGRect(x: x - 1.6 + dart, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(ink))
            case .worried:
                // Big glossy puppy eyes and raised brows.
                c.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: y - 5, width: 9, height: 11)), with: .color(ink))
                c.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 3.5, width: 3.2, height: 3.2)), with: .color(.white))
                let inner: Double = x < 50 ? 1 : -1
                stroke(&c, Path {
                    $0.move(to: CGPoint(x: x - 4 * inner, y: y - 8))
                    $0.addLine(to: CGPoint(x: x + 4 * inner, y: y - 11))
                }, width: 2)
            case .starving:
                // Heavy lids.
                c.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 2, width: 7, height: 7)), with: .color(ink))
                stroke(&c, Path { $0.move(to: CGPoint(x: x - 5, y: y - 1)); $0.addLine(to: CGPoint(x: x + 5, y: y - 1)) })
            case .content:
                c.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 4, width: 6, height: 8.5)), with: .color(ink))
            }
        }
    }

    private func drawMouth(_ c: inout GraphicsContext, t: Double) {
        let cx = 50.0, y = 43.0
        if mouthOpen {
            c.fill(Path(ellipseIn: CGRect(x: cx - 5, y: y - 4, width: 10, height: 8)), with: .color(ink))
            c.fill(Path(ellipseIn: CGRect(x: cx - 3, y: y + 0.5, width: 6, height: 3)), with: .color(Color(red: 0.93, green: 0.42, blue: 0.47)))
            return
        }
        switch mood {
        case .happy:
            var p = Path()
            p.move(to: CGPoint(x: cx - 9, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: cx + 9, y: y - 2), control: CGPoint(x: cx, y: y + 10))
            p.closeSubpath()
            c.fill(p, with: .color(ink))
        case .content:
            stroke(&c, Path { $0.move(to: CGPoint(x: cx - 7, y: y)); $0.addQuadCurve(to: CGPoint(x: cx + 7, y: y), control: CGPoint(x: cx, y: y + 5)) })
        case .overheated, .bloated:
            // Wobbly line.
            var p = Path()
            let phase = animated ? t * 6 : 0
            for i in 0...20 {
                let x = cx - 9 + Double(i) * 0.9
                let pt = CGPoint(x: x, y: y + sin(Double(i) * 0.9 + phase) * 1.8)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            stroke(&c, p, width: 2.2)
            if mood == .overheated {
                // Tongue out, panting.
                c.fill(Path(ellipseIn: CGRect(x: cx + 1, y: y + 1, width: 5, height: 6)), with: .color(Color(red: 0.93, green: 0.42, blue: 0.47)))
            }
        case .overwhelmed:
            c.stroke(Path(ellipseIn: CGRect(x: cx - 3.5, y: y - 3, width: 7, height: 8)), with: .color(ink), lineWidth: 2.4)
        case .sleepy:
            let yawn = animated ? (sin(t * 0.9) + 1) / 2 : 0.5
            c.fill(Path(ellipseIn: CGRect(x: cx - 3, y: y - 2, width: 6, height: 3 + yawn * 4)), with: .color(ink))
        case .starving, .cramped:
            stroke(&c, Path { $0.move(to: CGPoint(x: cx - 7, y: y + 3)); $0.addQuadCurve(to: CGPoint(x: cx + 7, y: y + 3), control: CGPoint(x: cx, y: y - 4)) })
        case .worried:
            var p = Path()
            p.move(to: CGPoint(x: cx - 6, y: y + 2))
            p.addCurve(to: CGPoint(x: cx + 6, y: y + 2), control1: CGPoint(x: cx - 2, y: y - 3), control2: CGPoint(x: cx + 2, y: y + 5))
            stroke(&c, p, width: 2.2)
        }
    }

    private func drawExtras(_ c: inout GraphicsContext, t: Double) {
        switch mood {
        case .happy, .worried:
            // Blush.
            for x in [30.0, 70.0] {
                c.fill(Path(ellipseIn: CGRect(x: x - 4, y: 34, width: 8, height: 4)), with: .color(Color(red: 0.95, green: 0.45, blue: 0.55).opacity(0.45)))
            }
        case .overheated:
            // A sweat drop sliding down the screen.
            let slide = animated ? (t * 0.7).truncatingRemainder(dividingBy: 1) : 0.3
            let y = 14 + slide * 14
            var drop = Path()
            drop.move(to: CGPoint(x: 76, y: y - 5))
            drop.addQuadCurve(to: CGPoint(x: 76, y: y + 3), control: CGPoint(x: 72, y: y + 2))
            drop.addQuadCurve(to: CGPoint(x: 76, y: y - 5), control: CGPoint(x: 80, y: y + 2))
            c.fill(drop, with: .color(Color(red: 0.36, green: 0.65, blue: 0.95)))
        case .sleepy:
            // Drifting Zzz.
            for i in 0..<3 {
                let phase = animated ? (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : Double(i) / 3
                let text = Text("z").font(.system(size: 7 + phase * 6, weight: .heavy, design: .rounded)).foregroundStyle(ink.opacity(1 - phase))
                c.draw(text, at: CGPoint(x: 70 + phase * 10, y: 22 - phase * 14))
            }
        case .starving:
            // Empty battery in the corner.
            let r = CGRect(x: 21, y: 12, width: 12, height: 6)
            c.stroke(Path(roundedRect: r, cornerRadius: 1.2), with: .color(ink), lineWidth: 1.2)
            c.fill(Path(CGRect(x: 33, y: 13.8, width: 1.4, height: 2.4)), with: .color(ink))
            let flash = !animated || Int(t * 2) % 2 == 0
            if flash {
                c.fill(Path(CGRect(x: 22.2, y: 13.2, width: 2, height: 3.6)), with: .color(Color(red: 0.86, green: 0.2, blue: 0.2)))
            }
        case .overwhelmed:
            // Little stress lines.
            for (i, a) in [200.0, 235.0, 305.0, 340.0].enumerated() {
                let wiggle = animated ? sin(t * 9 + Double(i)) * 0.8 : 0
                let rad = a * .pi / 180
                let p = Path {
                    $0.move(to: CGPoint(x: 50 + cos(rad) * 30, y: 30 + sin(rad) * 18 + wiggle))
                    $0.addLine(to: CGPoint(x: 50 + cos(rad) * 34, y: 30 + sin(rad) * 21 + wiggle))
                }
                stroke(&c, p, width: 1.6)
            }
        case .content, .bloated, .cramped:
            break
        }
    }
}
