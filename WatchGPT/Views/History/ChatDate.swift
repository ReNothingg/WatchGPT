import SwiftUI

enum ChatDate {
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return weekday.prefix(1).uppercased() + weekday.dropFirst()
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func messages(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "сообщение"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "сообщения"
        } else {
            word = "сообщений"
        }
        return "\(count) \(word)"
    }
}
