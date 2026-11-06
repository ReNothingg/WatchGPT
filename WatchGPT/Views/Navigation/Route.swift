import SwiftUI

enum Route: Hashable {
    case settings, models, usage, voice, history, diagnostics, clientVersion, quickPrompts, claude, places, privacy
    case gptChat(id: String, title: String)
}
