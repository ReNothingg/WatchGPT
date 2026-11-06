import AppIntents
import CoreLocation
import Foundation
import WidgetKit

struct SmartPlace: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double

    var region: CLCircularRegion {
        CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id.uuidString
        )
    }
}

enum SmartPlaceStore {
    private static let key = "smartStack.places.v1"
    static let radiusOptions: [Double] = [100, 150, 250, 500]
    static let defaultRadius: Double = 150

    static func noun(_ count: Int) -> String {
        let mod100 = count % 100, mod10 = count % 10
        if (11...14).contains(mod100) { return "мест" }
        if mod10 == 1 { return "место" }
        if (2...4).contains(mod10) { return "места" }
        return "мест"
    }

    static func load() -> [SmartPlace] {
        guard let data = SharedStore.defaults.data(forKey: key),
              let places = try? JSONDecoder().decode([SmartPlace].self, from: data) else {
            return []
        }
        return places
    }

    static func save(_ places: [SmartPlace]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        SharedStore.defaults.set(data, forKey: key)
    }

    private static let syncedKey = "smartPlaces.syncedFingerprint"

    static func syncRelevanceIfNeeded() async {
        let places = load()
        let fingerprint = (try? JSONEncoder().encode(places)) ?? Data()
        guard SharedStore.defaults.data(forKey: syncedKey) != fingerprint else { return }
        guard await syncRelevance(places) else { return }
        SharedStore.defaults.set(fingerprint, forKey: syncedKey)
    }

    @discardableResult
    static func syncRelevance(_ places: [SmartPlace]) async -> Bool {
        let intents = places.map { place in
            RelevantIntent(AskWidgetIntent(), widgetKind: SharedStore.askWidgetKind, relevance: .location(place.region))
        }
        do {
            try await RelevantIntentManager.shared.updateRelevantIntents(intents)
        } catch {
            return false
        }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.askWidgetKind)
        return true
    }
}

struct AskWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Спросить ChatGPT"
    static let description = IntentDescription("Виджет для быстрого вопроса голосом.")

    init() {}
}
