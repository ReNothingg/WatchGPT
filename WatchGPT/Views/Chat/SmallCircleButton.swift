import SwiftUI

struct SmallCircleButton: View {
    let icon: String
    var prominent = false
    var doubleTap = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SmallCircle(icon: icon, prominent: prominent)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .doubleTapAction(isEnabled: doubleTap)
        .accessibilityLabel(label)
    }
}

struct SmallCircle: View {
    let icon: String
    var prominent = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.secondaryText)
            .frame(width: 26, height: 26)
            .background(Circle().fill(prominent ? Theme.accent : Theme.raised))
            .contentShape(Circle())
    }
}
