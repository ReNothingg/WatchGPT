import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private init() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PowerMonitor.shared.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

enum AnimationRole {
    case decorative
    case status
    case feedback
}

struct LiveTimeline<Content: View>: View {
    var role: AnimationRole
    var fps: Double = 30
    var isActive = true
    var idleAfter: Duration?
    @ViewBuilder var content: (Date) -> Content

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isIdle = false
    @State private var wakeCount = 0

    private struct WakeKey: Hashable {
        var phase: ScenePhase
        var count: Int
    }

    var body: some View {
        let lowPower = PowerMonitor.shared.isLowPower
        TimelineView(.animation(minimumInterval: 1 / rate(lowPower: lowPower), paused: isPaused(lowPower: lowPower))) { context in
            content(context.date)
        }
        .onAppear { wakeCount += 1 }
        .task(id: WakeKey(phase: scenePhase, count: wakeCount)) {
            guard let idleAfter else { return }
            isIdle = false
            guard scenePhase == .active else { return }
            try? await Task.sleep(for: idleAfter)
            if !Task.isCancelled { isIdle = true }
        }
    }

    private func isPaused(lowPower: Bool) -> Bool {
        if !isActive || isLuminanceReduced || isIdle { return true }
        switch role {
        case .decorative: return lowPower || reduceMotion
        case .status: return reduceMotion
        case .feedback: return false
        }
    }

    private func rate(lowPower: Bool) -> Double {
        guard lowPower else { return fps }
        switch role {
        case .decorative, .status: return min(fps, 10)
        case .feedback: return min(fps, 15)
        }
    }
}
