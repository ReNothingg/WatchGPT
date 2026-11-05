import Charts
import SwiftUI

struct UsageHistoryChart: View {
    let days: [UsageDay]
    let weekly: Bool
    let windowLabel: String

    private func value(_ day: UsageDay) -> Double { weekly ? day.secondary : day.primary }

    var body: some View {
        let total = days.reduce(0) { $0 + value($1) }
        let today = days.last.map(value) ?? 0
        let peak = max(days.map(value).max() ?? 0, 5)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Расход по дням")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 4)
                Text("сегодня \(Theme.percent(today))")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
            Chart(days) { day in
                BarMark(
                    x: .value("День", day.day, unit: .day),
                    y: .value("Расход", value(day))
                )
                .foregroundStyle(Calendar.current.isDateInToday(day.day) ? Theme.accent : Theme.accent.opacity(0.45))
                .cornerRadius(2)
            }
            .chartYScale(domain: 0...peak)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { mark in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel {
                        if let v = mark.as(Double.self) {
                            Text("\(Int(v))%").font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 70)
            Text(total > 0
                 ? "За 7 дней \(Theme.percent(total)) · \(weekly ? "доля недельного лимита" : "доля окна «\(windowLabel)»")"
                 : "Пока нет данных: расход копится, пока приложение получает лимиты.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Расход лимита: сегодня \(Theme.percent(today)), за 7 дней \(Theme.percent(total))")
    }
}
