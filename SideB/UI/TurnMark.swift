import SwiftUI

/// The mark after the cover's hint: an arc going round a flat ellipse, like a coin seen edge-on turning,
/// with an arrowhead. Drawn in code (no SF Symbol). The back's mark is mirrored: it turns the other way.
/// Drawn in an 11 × 9 box; stroke it at about 1.3 pt.
struct TurnMark: Shape {
    var mirrored = false

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 11, sy = rect.height / 9
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + (mirrored ? 11 - x : x) * sx, y: rect.minY + y * sy)
        }
        // From the left of the ellipse, down round the bottom and right, to just past the top.
        let centre = (x: 5.5, y: 4.5), radius = (x: 4.0, y: 2.6)
        var path = Path()
        for step in 0...36 {
            let angle = (180 - 275 * Double(step) / 36) * .pi / 180
            let p = point(centre.x + radius.x * cos(angle), centre.y + radius.y * sin(angle))
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // The arrowhead, pointing on along the arc (leftwards at the top).
        let tipAngle = (180 - 275.0) * .pi / 180
        let tip = (x: centre.x + radius.x * cos(tipAngle), y: centre.y + radius.y * sin(tipAngle))
        path.move(to: point(tip.x + 1.7, tip.y - 1.3))
        path.addLine(to: point(tip.x, tip.y))
        path.addLine(to: point(tip.x + 1.7, tip.y + 1.3))
        return path
    }
}

/// The glass hint on a corner of the cover: a word and the turn mark.
struct TurnHint: View {
    let word: String
    var mirrored = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
            TurnMark(mirrored: mirrored)
                .stroke(Color(nsColor: .labelColor), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 9)
                .accessibilityHidden(true)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color(nsColor: .labelColor))
    }
}
