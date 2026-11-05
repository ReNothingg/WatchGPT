import WatchKit

enum Dictation {
    @MainActor
    @discardableResult
    static func present(_ completion: @escaping @MainActor (String) -> Void) -> Bool {
        guard let controller = WKApplication.shared().visibleInterfaceController
            ?? WKApplication.shared().rootInterfaceController else { return false }
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let text = results?.first as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { @MainActor in completion(text) }
        }
        return true
    }
}
