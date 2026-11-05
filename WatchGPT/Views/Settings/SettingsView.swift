import Charts
import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 8) {
                NavigationLink(value: Route.models) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Модель")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                            Text(store.selectedModel.displayName)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if store.selectedModel.efforts.count > 1 {
                                Text(ModelOption.effortLabel(store.effort))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer(minLength: 0)
                        Chevron()
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .padding(.vertical, 9)
                    .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ToggleTile(title: "Поиск", icon: "globe", isOn: $store.webSearch)
                    if store.selectedModel.supportsFast == true {
                        ToggleTile(title: "Fast", icon: "bolt.fill", isOn: $store.fastMode, onColor: Theme.fast, onText: .black)
                    }
                    ToggleTile(title: "Кратко", icon: "text.alignleft", isOn: $store.conciseAnswers)
                    ToggleTile(title: "Вслух", icon: "speaker.wave.2.fill", isOn: $store.autoSpeak)
                    ToggleTile(title: "На iPhone", icon: "iphone.and.arrow.forward", isOn: $store.handoff)
                }

                AnswerFontCard(scale: $store.answerFontScale)

                SettingsCard {
                    NavigationLink(value: Route.voice) {
                        SettingsRow(title: "Голос") {
                            Text(store.voiceEngine == .apple ? "Apple" : "OpenAI · \(store.transcribeModel.title.lowercased())")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.claude) {
                        SettingsRow(title: "Claude") {
                            if auth.hasClaudeKey {
                                Text(store.provider == .claude ? "включён" : "ключ есть")
                                    .foregroundStyle(store.provider == .claude ? Theme.claude : Theme.secondaryText)
                            } else {
                                Text("нет ключа")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.usage) {
                        SettingsRow(title: "Лимиты") {
                            if let left = store.usage?.tightest()?.remainingPercent() {
                                Text(Theme.percent(left))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.usageColor(left))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.places) {
                        SettingsRow(title: "Умная стопка") {
                            let count = PlaceRelevance.shared.places.count
                            Text(count == 0 ? "нет мест" : "\(count) \(SmartPlaceStore.noun(count))")
                                .foregroundStyle(Theme.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.diagnostics) {
                        SettingsRow(title: "Диагностика") {
                            let count = DiagnosticsLog.shared.entries.filter { $0.date.timeIntervalSinceNow > -86_400 }.count
                            if count > 0 {
                                Text("\(count)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                SettingsCard {
                    if let email = auth.tokens?.email {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(email)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let plan = store.usage?.planLabel ?? auth.tokens?.planType?.capitalized {
                                Text("ChatGPT \(plan)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        CardDivider()
                    }
                    Button {
                        confirmSignOut = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Выйти")
                                .font(.footnote)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Отключить аккаунт ChatGPT?", isPresented: $confirmSignOut) {
            Button("Выйти", role: .destructive) { auth.signOut() }
            Button("Отмена", role: .cancel) {}
        }
    }
}
