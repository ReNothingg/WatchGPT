import SwiftUI

struct CodeBlockView: View {
    let language: String
    let code: String
    let fontSize: CGFloat
    @Environment(\.codeLongPress) private var longPress
    @State private var expanded = false
    @State private var sentToPhone = false

    private var lineCount: Int {
        code.isEmpty ? 0 : code.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private var title: String {
        if sentToPhone { return "Открой на iPhone" }
        let name = language.isEmpty ? "Код" : language
        return "\(name) · \(lineCount) \(Self.linesWord(lineCount))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: sentToPhone ? "iphone.and.arrow.forward" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: fontSize * 0.7, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: fontSize * 0.78, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: fontSize * 0.65, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(sentToPhone ? Theme.accent : Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expanded.toggle() }
            .animation(.smooth(duration: 0.3), value: sentToPhone)

            if expanded {
                Rectangle()
                    .fill(Theme.track)
                    .frame(height: 0.5)
                HorizontalPan {
                    Text(CodeHighlighter.highlight(code, language: language))
                        .font(.system(size: (fontSize * 0.74).rounded(), design: .monospaced))
                        .fixedSize()
                        .padding(8)
                }
            }
        }
        .background(Theme.surfaceDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.track, lineWidth: 0.5))
        .pressPop(longPress.map { send in { sendToPhone(send) } })
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Открыть на iPhone") { if let longPress { sendToPhone(longPress) } }
    }

    private func sendToPhone(_ send: (String, String) -> Void) {
        send(code, language)
        sentToPhone = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            sentToPhone = false
        }
    }

    private static func linesWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1, mod100 != 11 { return "строка" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "строки" }
        return "строк"
    }
}
