import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class PlaceRelevance: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceRelevance()

    enum LocateError: LocalizedError {
        case denied, failed, inaccurate

        var errorDescription: String? {
            switch self {
            case .denied: "Нет доступа к геопозиции. Разрешите его в настройках часов."
            case .failed: "Не удалось определить место. Попробуйте ещё раз."
            case .inaccurate: "Слишком неточная геопозиция. Выйдите ближе к окну и повторите."
            }
        }
    }

    private(set) var places: [SmartPlace] = SmartPlaceStore.load()
    private(set) var isLocating = false
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    @ObservationIgnored private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func sync() async {
        await SmartPlaceStore.syncRelevance(places)
    }

    func addCurrentPlace(name: String, radius: Double) async throws {
        isLocating = true
        defer { isLocating = false }

        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
            throw LocateError.denied
        }

        let location: CLLocation? = await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
        guard let location else { throw LocateError.failed }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 300 else { throw LocateError.inaccurate }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SmartPlace(
            name: trimmed.isEmpty ? "Место \(places.count + 1)" : trimmed,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: max(radius, location.horizontalAccuracy)
        )
        places.append(place)
        persist()
    }

    func remove(_ place: SmartPlace) {
        places.removeAll { $0.id == place.id }
        persist()
    }

    func updateRadius(_ place: SmartPlace, radius: Double) {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].radius = radius
        persist()
    }

    private func persist() {
        SmartPlaceStore.save(places)
        let snapshot = places
        Task { await SmartPlaceStore.syncRelevance(snapshot) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard status != .notDetermined, let continuation = self.authContinuation else { return }
            self.authContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let best = locations.min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: best)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
