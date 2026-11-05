import SwiftUI

struct ScrollChromeMetrics: Equatable {
    var offset: CGFloat
    var remaining: CGFloat
}

@available(watchOS 11.0, *)
struct ScrollChromeModifier: ViewModifier {
    @Binding var visible: Bool
    @State private var lastOffset: CGFloat?
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollChromeMetrics.self) { geo in
                ScrollChromeMetrics(
                    offset: geo.contentOffset.y,
                    remaining: geo.contentSize.height - geo.visibleRect.maxY
                )
            } action: { _, metrics in
                update(metrics)
            }
    }

    private func update(_ metrics: ScrollChromeMetrics) {
        defer { lastOffset = metrics.offset }
        if metrics.remaining < 48 {
            travel = 0
            set(true)
            return
        }
        guard let lastOffset else { return }
        let delta = metrics.offset - lastOffset
        guard abs(delta) > 0.5 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel > 28 {
            set(false)
        } else if travel < -28 {
            set(true)
        }
    }

    private func set(_ value: Bool) {
        guard visible != value else { return }
        withAnimation(.snappy(duration: 0.25)) { visible = value }
    }
}

extension View {
    @ViewBuilder
    func autoHidesChrome(_ visible: Binding<Bool>) -> some View {
        if #available(watchOS 11.0, *) {
            modifier(ScrollChromeModifier(visible: visible))
        } else {
            self
        }
    }

    func chromeVisibility(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            .allowsHitTesting(visible)
    }
}
