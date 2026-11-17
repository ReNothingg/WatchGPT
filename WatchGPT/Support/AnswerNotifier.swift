import Foundation
import UserNotifications

enum AnswerNotifier {
    private static let identifier = "answer.ready"

    static func prepare() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    static func post(question: String, answer: String, chatID: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            break
        default:
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = question.isEmpty ? String(localized: "Ответ готов") : question
        content.body = answer
        content.sound = .default
        content.threadIdentifier = chatID

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
