import Foundation
import UserNotifications

enum LimitReminder {
    private static let identifier = "limit.reset"

    static func update(for usage: UsageSnapshot?) {
        schedule(at: resetDate(for: usage))
    }

    static func schedule(at date: Date?) {
        Task { await apply(date) }
    }

    static func resetDate(for usage: UsageSnapshot?, now: Date = .now) -> Date? {
        guard let usage else { return nil }
        let windows = [usage.primary, usage.secondary].compactMap { $0 }
        var exhausted = windows.filter { $0.remainingPercent(at: now) <= 0 }
        if exhausted.isEmpty, usage.limitReached, let tightest = usage.tightest(at: now) {
            exhausted = [tightest]
        }
        let dates = exhausted.compactMap(\.resetAt).filter { $0 > now }
        guard !exhausted.isEmpty, dates.count == exhausted.count else { return nil }
        return dates.max()
    }

    private static func apply(_ date: Date?) async {
        let center = UNUserNotificationCenter.current()
        guard let date, date > .now else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        case .denied:
            return
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Лимит восстановлен"
        content.body = "Можно снова спрашивать ChatGPT."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
