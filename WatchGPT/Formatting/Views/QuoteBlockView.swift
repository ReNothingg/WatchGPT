import SwiftUI

struct QuoteBlockView: View {
    let text: String
    let fontSize: CGFloat
    let font: Font
    var live = false

    var body: some View {
        HStack(alignment: .top, spacing: (fontSize * 0.45).rounded()) {
            Capsule()
                .fill(Theme.secondaryText.opacity(0.55))
                .frame(width: 2.5)
            MathRichText(text: text, fontSize: fontSize, font: font, live: live)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
    }
}
