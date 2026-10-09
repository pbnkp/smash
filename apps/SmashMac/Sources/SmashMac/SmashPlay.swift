import SwiftUI

/// The Smash mark in motion: a trail into one lit core.
/// The same drawing is `ui/graphic/smash-play.html` for snoutOS,
/// and the compact player mounted in TimeDrive and SnoutSession.
struct SmashPlay: View {
    var compact: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let phase = reduceMotion ? 0.72 : (t.truncatingRemainder(dividingBy: 2.6) / 2.6)
                let tip = w * (0.18 + 0.46 * phase)
                var trail = Path()
                trail.move(to: CGPoint(x: 8, y: h * 0.50))
                trail.addLine(to: CGPoint(x: tip, y: h * 0.50))
                ctx.stroke(
                    trail,
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0),
                                          Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.85)]),
                        startPoint: CGPoint(x: 8, y: h * 0.5),
                        endPoint: CGPoint(x: tip, y: h * 0.5)
                    ),
                    style: StrokeStyle(lineWidth: compact ? 3 : 6, lineCap: .round)
                )
                let r = min(w, h) * (compact ? 0.28 : 0.22)
                let c = CGPoint(x: min(w - r - 8, max(tip, w * 0.62)), y: h * 0.50)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(
                    Path(ellipseIn: rect.insetBy(dx: -r * 0.35, dy: -r * 0.35)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.55), .clear]),
                        center: c,
                        startRadius: 0,
                        endRadius: r * 1.6
                    )
                )
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.88, green: 0.95, blue: 1), location: 0),
                            .init(color: Color(red: 0.22, green: 0.74, blue: 0.97), location: 0.22),
                            .init(color: Color(red: 0.01, green: 0.41, blue: 0.63), location: 0.62),
                            .init(color: .black, location: 1)
                        ]),
                        center: c,
                        startRadius: 0,
                        endRadius: r
                    )
                )
            }
        }
        .frame(height: compact ? 84 : 168)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 18, style: .continuous))
        .accessibilityLabel("Smash graphic")
    }
}
