import SwiftUI
import WidgetKit

@main
struct WatchGPTWidgets: WidgetBundle {
    var body: some Widget {
        AskWidget()
        AnswerWidget()
        LimitsWidget()
        if #available(watchOS 26.0, *) {
            AskControl()
        }
    }
}

@available(watchOS 26.0, *)
struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "WatchGPTAskControl") {
            ControlWidgetButton(action: AskChatGPTIntent()) {
                Label("Спросить ChatGPT", systemImage: "mic.fill")
            }
            .tint(Theme.accent)
        }
        .displayName("Спросить ChatGPT")
        .description("Открывает WatchGPT и сразу включает диктовку.")
    }
}
