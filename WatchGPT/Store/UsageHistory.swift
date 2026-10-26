import Foundation
import Observation

struct UsageDay: Codable, Equatable, Identifiable, Sendable {
    var day: Date
    var primary: Double = 0
    var secondary: Double = 0

    var id: Date { day }
}

@MainActor
@Observable
final class UsageHistory {
    private struct Mark: Codable, Equatable {
        var used: Double
        var resetAt: Date?
    }

    private struct Stored: Codable {
        var days: [UsageDay]
        var primary: Mark?
        var secondary: Mark?
    }

    private(set) var days: [UsageDay] = []
    @ObservationIgnored private var primaryMark: Mark?
    @ObservationIgnored private var secondaryMark: Mark?

    private static let key = "usage.history.v1"
    private static let keepDays = 30
    private static let rolloverTolerance: TimeInterval = 600
    private let defaults = UserDefaults.standard

    init() {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        days = stored.days
        primaryMark = stored.primary
        secondaryMark = stored.secondary
    }

    var isEmpty: Bool { primaryMark == nil && secondaryMark == nil }

    func record(_ snapshot: UsageSnapshot, at date: Date = .now) {
        let primary = snapshot.primary.map { Self.spent(since: primaryMark, now: $0) } ?? 0
        let secondary = snapshot.secondary.map { Self.spent(since: secondaryMark, now: $0) } ?? 0
        let newPrimary = snapshot.primary.map { Mark(used: $0.usedPercent, resetAt: $0.resetAt) } ?? primaryMark
        let newSecondary = snapshot.secondary.map { Mark(used: $0.usedPercent, resetAt: $0.resetAt) } ?? secondaryMark
        let marksChanged = newPrimary != primaryMark || newSecondary != secondaryMark
        primaryMark = newPrimary
        secondaryMark = newSecondary

        if primary > 0 || secondary > 0 {
            let day = Calendar.current.startOfDay(for: date)
            if let index = days.lastIndex(where: { $0.day == day }) {
                days[index].primary += primary
                days[index].secondary += secondary
            } else {
                days.append(UsageDay(day: day, primary: primary, secondary: secondary))
                days.sort { $0.day < $1.day }
                trim(now: date)
            }
        } else if !marksChanged {
            return
        }
        save()
    }

    func recent(_ count: Int, now: Date = .now) -> [UsageDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return days.first { $0.day == day } ?? UsageDay(day: day)
        }
    }

    func clear() {
        days = []
        primaryMark = nil
        secondaryMark = nil
        defaults.removeObject(forKey: Self.key)
    }

    private static func spent(since mark: Mark?, now window: UsageWindow) -> Double {
        guard let mark else { return 0 }
        if let old = mark.resetAt, let new = window.resetAt, new.timeIntervalSince(old) > rolloverTolerance {
            return max(0, window.usedPercent)
        }
        let diff = window.usedPercent - mark.used
        if diff < -1 { return max(0, window.usedPercent) }
        return max(0, diff)
    }

    private func trim(now: Date) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Calendar.current.startOfDay(for: now)) else { return }
        days.removeAll { $0.day < cutoff }
    }

    private func save() {
        let stored = Stored(days: days, primary: primaryMark, secondary: secondaryMark)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.key) }
    }
}
