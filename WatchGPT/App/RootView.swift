import AppIntents
import SwiftUI
import WatchKit

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ChatStore.self) private var store

    var body: some View {
        Group {
            if auth.isSignedIn {
                NavigationStack(path: Bindable(store).path) {
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
        .onChange(of: auth.claudeKey) { _, _ in
            store.claudeKeyChanged()
        }
        .task {
            if AskRequest.consume() { store.pendingAsk = true }
            store.publishWidget()
            store.resumePendingIfNeeded()
            Task { await PlaceRelevance.shared.sync() }
            if auth.isSignedIn, auth.apiKey == nil, store.usesCloudVoice {
                Task { _ = try? await auth.obtainAPIKey() }
            }
            await store.refreshMeta(force: true)
        }
    }
}
