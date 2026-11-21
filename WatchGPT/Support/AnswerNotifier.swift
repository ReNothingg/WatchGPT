import Foundation
import UserNotifications
import WatchKit

enum AnswerNotifier {
    fileprivate static let identifier = "answer.ready"

    static func prepare() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    @MainActor
    static func signal(question: String, answer: String, chatID: String) async {
        guard WKApplication.shared().applicationState != .active else {
            WKInterfaceDevice.current().play(.notification)
            return
        }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = question.isEmpty ? String(localized: "Ответ готов") : question
        content.body = answer
        content.sound = .default
        content.threadIdentifier = chatID

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }
}

final class WatchNotificationDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == AnswerNotifier.identifier else { return [] }
        return [.banner, .list, .sound]
    }
}
