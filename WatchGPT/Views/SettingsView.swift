import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var store = store

        List {
            Section {
                NavigationLink(value: Route.models) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Модель")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(store.selectedModel.displayName)
                    }
                }

                if store.selectedModel.efforts.count > 1 {
                    Picker("Размышление", selection: $store.effort) {
                        ForEach(store.selectedModel.efforts, id: \.self) { effort in
                            Text(ModelOption.effortLabel(effort)).tag(effort)
                        }
                    }
                }
            }

            Section {
                Toggle("Поиск в сети", isOn: $store.webSearch)
                Toggle("Короткие ответы", isOn: $store.conciseAnswers)
                Toggle("Читать вслух", isOn: $store.autoSpeak)
            } footer: {
                Text("Двойное касание ответа — прочитать его вслух.")
            }

            Section {
                NavigationLink(value: Route.usage) {
                    HStack {
                        Text("Лимиты")
                        Spacer()
                        if let left = store.usage?.tightest()?.remainingPercent() {
                            Text(Theme.percent(left))
                                .foregroundStyle(Theme.usageColor(left))
                                .monospacedDigit()
                        }
                    }
                }
                Button {
                    store.newChat()
                } label: {
                    Label("Новый чат", systemImage: "square.and.pencil")
                }
            }

            Section {
                if let email = auth.tokens?.email {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email).font(.footnote).lineLimit(1)
                        if let plan = store.usage?.planLabel ?? auth.tokens?.planType?.capitalized {
                            Text("ChatGPT \(plan)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Отключить аккаунт ChatGPT?", isPresented: $confirmSignOut) {
            Button("Выйти", role: .destructive) { auth.signOut() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct ModelPickerView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(store.models) { model in
                Button {
                    store.selectedModelSlug = model.slug
                    WKHaptics.click()
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            if let summary = model.summary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        if model.slug == store.selectedModelSlug {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle("Модель")
    }
}

struct UsageView: View {
    @Environment(ChatStore.self) private var store
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let usage = store.usage, usage.primary != nil || usage.secondary != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                if let w = usage.primary { WindowGauge(window: w, now: context.date) }
                                if let w = usage.secondary { WindowGauge(window: w, now: context.date) }
                            }
                            VStack(spacing: 4) {
                                if let w = usage.primary { resetLine(w, now: context.date) }
                                if let w = usage.secondary { resetLine(w, now: context.date) }
                            }
                        }
                    }
                    if let plan = usage.planLabel {
                        Text("ChatGPT \(plan)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = store.usageError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView().padding(.top, 20)
                }

                Button {
                    Task {
                        refreshing = true
                        await store.refreshUsage()
                        refreshing = false
                    }
                } label: {
                    if refreshing { ProgressView() } else { Label("Обновить", systemImage: "arrow.clockwise") }
                }
                .disabled(refreshing)

                Text("Сколько осталось от лимитов вашей подписки. Окно сбрасывается само.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Лимиты")
        .task { await store.refreshUsage() }
    }

    private func resetLine(_ window: UsageWindow, now: Date) -> some View {
        HStack {
            Text(window.longLabel)
            Spacer()
            if let reset = window.resetAt, reset > now {
                Text("сброс \(reset.formatted(.relative(presentation: .numeric)))")
                    .foregroundStyle(.secondary)
            } else {
                Text("сброшен").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }
}

private struct WindowGauge: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        let left = window.remainingPercent(at: now)
        VStack(spacing: 4) {
            ZStack {
                UsageRing(remaining: left, lineWidth: 6, showsText: false)
                VStack(spacing: 0) {
                    Text(Theme.percent(left))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("осталось")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)
            Text(window.shortLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
