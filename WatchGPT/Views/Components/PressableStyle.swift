import SwiftUI

extension View {
    @ViewBuilder
    func doubleTapAction(isEnabled: Bool = true) -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction, isEnabled: isEnabled)
        } else {
            self
        }
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
