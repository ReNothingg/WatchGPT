import SwiftUI

enum Theme {
    /// ChatGPT green.
    static let accent = Color(red: 0.188, green: 0.835, blue: 0.784)
    static let bubble = Color(red: 0.149, green: 0.149, blue: 0.157)
    static let chip = Color.white.opacity(0.10)
    static let control = Color(white: 0.2)
    static let surface = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let surfaceDim = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let raised = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let track = Color(red: 0.227, green: 0.227, blue: 0.235)
    static let secondaryText = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let fast = Color(red: 1.0, green: 0.839, blue: 0.039)
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)

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
