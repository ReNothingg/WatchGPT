import SwiftUI

private struct TableLongPressKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct CodeLongPressKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}

extension EnvironmentValues {
    var tableLongPress: (() -> Void)? {
        get { self[TableLongPressKey.self] }
        set { self[TableLongPressKey.self] = newValue }
    }

    var codeLongPress: ((String, String) -> Void)? {
        get { self[CodeLongPressKey.self] }
        set { self[CodeLongPressKey.self] = newValue }
    }
}

private struct PressPop: ViewModifier {
    let action: () -> Void
    @State private var pressing = false
    @State private var popped = false

    private var scale: CGFloat { popped ? 1.08 : pressing ? 1.05 : 1 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .brightness(pressing || popped ? 0.04 : 0)
            .shadow(color: .black.opacity(pressing || popped ? 0.6 : 0), radius: pressing || popped ? 10 : 0, y: 4)
            .zIndex(pressing || popped ? 1 : 0)
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 8) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { popped = true }
                action()
                Task {
                    try? await Task.sleep(for: .milliseconds(260))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { popped = false }
                }
            } onPressingChanged: { isPressing in
                withAnimation(isPressing ? .easeOut(duration: 0.5) : .spring(response: 0.3, dampingFraction: 0.6)) {
                    pressing = isPressing
                }
            }
    }
}

extension View {
    @ViewBuilder
    func pressPop(_ action: (() -> Void)?) -> some View {
        if let action {
            modifier(PressPop(action: action))
        } else {
            self
        }
    }
}
