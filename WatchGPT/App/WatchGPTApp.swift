import SwiftUI
import WatchKit

@main
struct WatchGPTApp: App {
    @State private var auth: AuthService
    @State private var store: ChatStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _store = State(initialValue: ChatStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(store)
                .tint(Theme.accent)
                .onOpenURL { store.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refreshMeta() }
            } else if phase == .background {
                store.publishWidget()
            }
        }
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ChatStore.self) private var store

    var body: some View {
        Group {
            if auth.isSignedIn {
                NavigationStack {
                    ChatView()
                }
            } else {
                NavigationStack {
                    PairingView()
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                WKHaptics.success()
                Task { await store.refreshMeta(force: true) }
                Task { if auth.apiKey == nil { _ = try? await auth.obtainAPIKey() } }
            } else {
                store.signedOut()
            }
            store.publishWidget()
        }
        .task {
            store.publishWidget()
            if auth.isSignedIn, auth.apiKey == nil, store.usesCloudVoice {
                Task { _ = try? await auth.obtainAPIKey() }
            }
            await store.refreshMeta(force: true)
        }
    }
}

enum WKHaptics {
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func click() { WKInterfaceDevice.current().play(.click) }
}
