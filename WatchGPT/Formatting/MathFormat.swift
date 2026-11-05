import SwiftUI

enum MathFormat {
    enum Block {
        case text(String)
        case math(String)
        case code(String, String)
        case table([[String]], [TableAlign])
        case list([ListItem])
        case quote(String)
    }

    enum TableAlign {
        case leading, center, trailing
    }

    enum ListMarker {
        case bullet
        case number(String)
        case task(Bool)
    }

    struct ListItem {
        let level: Int
        let marker: ListMarker
        var text: String
    }
}
