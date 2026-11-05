import SwiftUI

indirect enum MathNode {
    case row([MathNode])
    case atom(String, MathAtom)
    case text(String, bold: Bool)
    case frac(MathNode, MathNode, bar: Bool)
    case sqrt(MathNode, index: MathNode?)
    case scripts(MathNode, sup: MathNode?, sub: MathNode?)
    case limits(MathNode, over: MathNode?, under: MathNode?)
    case fenced(String, MathNode, String)
    case accent(MathNode, MathAccent)
    case table([[MathNode]], MathTable)
    case space(CGFloat)

    static let empty = MathNode.row([])
}

enum MathAtom {
    case ident, number, symbol, bin, rel, open, close, punct, fn, largeOp
}

enum MathAccent {
    case vec, hat, bar, dot, ddot, tilde, overline, underline
}

enum MathTable: Equatable {
    case matrix(String, String)
    case cases
    case aligned
}

enum MathClass {
    case ord, op, bin, rel, open, close, punct
}
