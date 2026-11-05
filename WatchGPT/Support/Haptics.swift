import AppIntents
import SwiftUI
import WatchKit

enum WKHaptics {
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func click() { WKInterfaceDevice.current().play(.click) }

    static func level(_ index: Int, of count: Int) {
        let scale: [WKHapticType] = [.click, .directionUp, .start, .success, .notification]
        guard count > 1 else { return click() }
        let fraction = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        WKInterfaceDevice.current().play(scale[Int((fraction * Double(scale.count - 1)).rounded())])
    }
}
