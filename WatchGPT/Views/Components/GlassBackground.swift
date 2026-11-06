import SwiftUI

extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(
        _ shape: S,
        fill: Color = Theme.surface,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(watchOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(shape.fill(fill))
        }
    }

    @ViewBuilder
    func glassGroup(spacing: CGFloat? = nil) -> some View {
        if #available(watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}
