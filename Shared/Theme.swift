import SwiftUI

enum Theme {
    /// ChatGPT green.
    static let accent = Color(red: 0.063, green: 0.639, blue: 0.498)
    static let bubble = Color.white.opacity(0.13)
    static let chip = Color.white.opacity(0.10)

    static func usageColor(_ remainingPercent: Double) -> Color {
        switch remainingPercent {
        case 50...: return accent
        case 20..<50: return .yellow
        case 8..<20: return .orange
        default: return .red
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
