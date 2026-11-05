import AppIntents
import SwiftUI
import WatchKit

@main
struct WatchGPTApp: App {
    @State private var auth: AuthService
    @State private var store: ChatStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = AuthService()
        let store = ChatStore(auth: auth)
        _auth = State(initialValue: auth)
        _store = State(initialValue: store)
        AppDependencyManager.shared.add(dependency: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(store)
                .tint(Theme.accent)
                .onOpenURL { store.handle(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: .watchGPTAskRequested)) { _ in
                    if AskRequest.consume() { store.pendingAsk = true }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.sceneBecameActive()
                if AskRequest.consume() { store.pendingAsk = true }
                Task { await store.refreshMeta() }
            } else if phase == .background {
                store.sceneEnteredBackground()
                store.publishWidget()
            }
        }
    }
}
