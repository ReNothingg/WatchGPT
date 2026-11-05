import Charts
import SwiftUI

struct EffortBar: View {
    let efforts: [String]
    @Binding var selection: String
    var crownByDefault = false
    @State private var crown: Double = 0
    @FocusState private var focused: Bool

    private var index: Int { efforts.firstIndex(of: selection) ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let count = max(efforts.count, 1)
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Theme.accent : Theme.track)
                        .frame(height: 5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        focused = true
                        guard geo.size.width > 0 else { return }
                        let raw = value.location.x / geo.size.width * CGFloat(count)
                        select(Int(raw.rounded(.down)))
                    }
            )
        }
        .frame(height: 16)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            $crown,
            from: 0,
            through: Double(max(efforts.count - 1, 0)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onAppear {
            crown = Double(index)
            if crownByDefault { focused = true }
        }
        .onChange(of: crown) { _, value in
            select(Int(value.rounded()))
        }
        .onChange(of: selection) { _, _ in
            if Int(crown.rounded()) != index { crown = Double(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Уровень рассуждений")
        .accessibilityValue(ModelOption.effortLabel(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(index + 1)
            case .decrement: select(index - 1)
            @unknown default: break
            }
        }
    }

    private func select(_ i: Int) {
        guard !efforts.isEmpty else { return }
        let clamped = min(max(i, 0), efforts.count - 1)
        guard efforts[clamped] != selection else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = efforts[clamped] }
        WKHaptics.level(clamped, of: efforts.count)
    }
}
