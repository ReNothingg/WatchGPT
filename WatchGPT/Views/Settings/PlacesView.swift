import SwiftUI
import WatchKit

struct PlacesView: View {
    @State private var relevance = PlaceRelevance.shared
    @State private var name = ""
    @State private var radius = SmartPlaceStore.defaultRadius
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                Text("Когда вы окажетесь в одном из этих мест, виджет «Спросить ChatGPT» поднимется наверх смарт-стопки.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }

            if !relevance.places.isEmpty {
                Section("Места") {
                    ForEach(relevance.places) { place in
                        PlaceRow(place: place) { newRadius in
                            relevance.updateRadius(place, radius: newRadius)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                relevance.remove(place)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Новое место") {
                TextField("Название", text: $name)
                Picker("Радиус", selection: $radius) {
                    ForEach(SmartPlaceStore.radiusOptions, id: \.self) { value in
                        Text("\(Int(value)) м").tag(value)
                    }
                }
                Button {
                    Task { await addPlace() }
                } label: {
                    HStack(spacing: 6) {
                        if relevance.isLocating {
                            ProgressView()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(relevance.isLocating ? "Определяю…" : "Запомнить это место")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.accent)
                }
                .disabled(relevance.isLocating)

                if let errorText {
                    Text(errorText)
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                } else if relevance.isDenied {
                    Text("Доступ к геопозиции выключен. Включите его: Настройки → Конфиденциальность → Службы геолокации → WatchGPT.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .navigationTitle("Умная стопка")
    }

    private func addPlace() async {
        errorText = nil
        do {
            try await relevance.addCurrentPlace(name: name, radius: radius)
            name = ""
            WKHaptics.success()
        } catch {
            errorText = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

private struct PlaceRow: View {
    let place: SmartPlace
    let onRadius: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text(place.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            Button {
                let options = SmartPlaceStore.radiusOptions
                let next = options.first { $0 > place.radius } ?? options[0]
                WKHaptics.click()
                onRadius(next)
            } label: {
                HStack(spacing: 3) {
                    Text("Радиус \(Int(place.radius)) м")
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
