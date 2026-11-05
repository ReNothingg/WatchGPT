import SwiftUI

struct MarkdownText: View {
    let text: String
    var style: Font.TextStyle = .body
    var scale: Double = 1
    var live = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let base = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
        if scale == 1 {
            MathRichText(text: text, fontSize: base, font: .system(style), live: live)
        } else {
            let size = (base * scale).rounded()
            MathRichText(text: text, fontSize: size, font: .system(size: size), live: live)
        }
    }

    private var uiStyle: UIFont.TextStyle {
        switch style {
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        default: return .body
        }
    }
}
