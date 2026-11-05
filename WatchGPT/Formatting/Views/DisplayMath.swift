import SwiftUI

struct DisplayMath: View {
    let node: MathNode
    let fontSize: CGFloat

    init(latex: String, fontSize: CGFloat) {
        node = MathFormat.parsed(latex)
        self.fontSize = fontSize
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            MathView(node: node, fs: fontSize * 1.08)
            MathView(node: node, fs: fontSize * 0.92)
            MathView(node: node, fs: fontSize * 0.8)
            ScrollView(.horizontal, showsIndicators: false) {
                MathView(node: node, fs: fontSize * 0.86)
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct MathView: View {
    let node: MathNode
    let fs: CGFloat

    var body: some View {
        MathDraw.view(node, fs: fs, display: true)
            .fixedSize()
    }
}
