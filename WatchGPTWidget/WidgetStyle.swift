import SwiftUI
import WidgetKit

enum RingPalette {
    static let mint = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let cyan = Color(red: 0.70, green: 0.70, blue: 0.72)
    static let violet = Color(red: 0.50, green: 0.50, blue: 0.52)

    static func color(_ index: Int, _ remaining: Double) -> Color {
        if remaining < 20 { return Theme.usageColor(remaining) }
        return index == 0 ? mint : cyan
    }
}

struct ActivityRing {
    let fraction: Double
    let color: Color
}

struct ActivityRings: View {
    let rings: [ActivityRing]
    var placeholderCount: Int = 1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let items = rings.isEmpty
                ? Array(repeating: ActivityRing(fraction: 0, color: RingPalette.mint), count: placeholderCount)
                : rings
            let line = side * (items.count > 1 ? 0.17 : 0.2)
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, ring in
                    let inset = CGFloat(index) * (line + side * 0.03) + line / 2
                    Circle()
                        .inset(by: inset)
                        .stroke(ring.color.opacity(0.22), lineWidth: line)
                    if ring.fraction > 0 {
                        Circle()
                            .inset(by: inset)
                            .trim(from: 0, to: min(1, ring.fraction))
                            .stroke(ring.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StatLine: View {
    let value: String
    let unit: String?
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).smallCaps())
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .widgetAccentable()
    }
}
