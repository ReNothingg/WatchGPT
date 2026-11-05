import Charts
import SwiftUI

struct ModelCard: View {
    @Environment(ChatStore.self) private var store
    var crownControlsEffort = false

    var body: some View {
        @Bindable var store = store
        let model = store.selectedModel
        let hasEfforts = model.efforts.count > 1
        let defaultEffort = model.defaultEffort ?? model.efforts.first ?? store.effort

        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if model.supportsFast == true {
                    Button {
                        store.fastMode.toggle()
                        WKHaptics.click()
                    } label: {
                        Image(systemName: store.fastMode ? "bolt.fill" : "bolt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(store.fastMode ? Theme.fast : Theme.secondaryText)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.fastMode ? "Fast включён" : "Fast выключен")
                } else {
                    Color.clear.frame(width: 30, height: 30)
                }

                NavigationLink(value: Route.models) {
                    VStack(spacing: 0) {
                        Text(hasEfforts ? ModelOption.effortLabel(store.effort) : model.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        HStack(spacing: 2) {
                            Text(hasEfforts ? model.displayName : "Сменить модель")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Выбрать модель")

                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.effort = defaultEffort }
                    WKHaptics.click()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hasEfforts && store.effort != defaultEffort ? 1 : 0)
                .disabled(!hasEfforts || store.effort == defaultEffort)
                .accessibilityLabel("Сбросить уровень")
            }

            if hasEfforts {
                EffortBar(efforts: model.efforts, selection: $store.effort, crownByDefault: crownControlsEffort)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 4)
        .padding(.bottom, hasEfforts ? 6 : 4)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surfaceDim))
    }
}
