import Foundation

/// Minimal QR Code generator (byte mode), ported from Project Nayuki's
/// QR Code generator library (MIT License, https://www.nayuki.io/page/qr-code-generator-library).
/// watchOS has no CoreImage, so the pairing QR is drawn from this matrix.
struct QRCode {
    enum ECC: Int {
        case low = 0, medium, quartile, high

        var formatBits: Int {
            switch self {
            case .low: return 1
            case .medium: return 0
            case .quartile: return 3
            case .high: return 2
            }
        }
    }

    let version: Int
    let size: Int
    let ecc: ECC
    private(set) var mask: Int
    private(set) var modules: [[Bool]]
    private var isFunction: [[Bool]]

    /// Returns true for a dark module. Coordinates are (x: column, y: row).
    func isDark(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return modules[y][x]
    }

    // MARK: Encoding

    static func encode(_ text: String, ecc: ECC = .medium, boostECC: Bool = true, forcedMask: Int? = nil) -> QRCode? {
        encode(bytes: Array(text.utf8), ecc: ecc, boostECC: boostECC, forcedMask: forcedMask)
    }

    static func encode(bytes: [UInt8], ecc requested: ECC, boostECC: Bool = true, forcedMask: Int? = nil) -> QRCode? {
        var ecc = requested
        var version = 1
        var dataUsedBits = 0
        while true {
            let capacityBits = numDataCodewords(version: version, ecc: ecc) * 8
            let used = 4 + charCountBits(version: version) + bytes.count * 8
            if used <= capacityBits {
                dataUsedBits = used
                break
            }
            version += 1
            if version > 40 { return nil }
        }

        if boostECC {
            for candidate in [ECC.medium, .quartile, .high] where candidate.rawValue > ecc.rawValue {
                if dataUsedBits <= numDataCodewords(version: version, ecc: candidate) * 8 {
                    ecc = candidate
                }
            }
        }

        var bits = BitBuffer()
        bits.append(0x4, count: 4) // byte mode
        bits.append(bytes.count, count: charCountBits(version: version))
        for b in bytes { bits.append(Int(b), count: 8) }

        let capacityBits = numDataCodewords(version: version, ecc: ecc) * 8
        bits.append(0, count: min(4, capacityBits - bits.count))
        bits.append(0, count: (8 - bits.count % 8) % 8)
        var pad = 0xEC
        while bits.count < capacityBits {
            bits.append(pad, count: 8)
            pad ^= 0xEC ^ 0x11
        }

        var codewords = [UInt8](repeating: 0, count: bits.count / 8)
        for (i, bit) in bits.bits.enumerated() where bit {
            codewords[i >> 3] |= UInt8(1 << (7 - (i & 7)))
        }

        return QRCode(version: version, ecc: ecc, dataCodewords: codewords, forcedMask: forcedMask)
    }

    private init(version: Int, ecc: ECC, dataCodewords: [UInt8], forcedMask: Int?) {
        self.version = version
        self.ecc = ecc
        self.size = version * 4 + 17
        self.modules = Array(repeating: Array(repeating: false, count: size), count: size)
        self.isFunction = modules
        self.mask = 0

        drawFunctionPatterns()
        let allCodewords = addEccAndInterleave(dataCodewords)
        drawCodewords(allCodewords)

        var chosen = forcedMask ?? -1
        if chosen < 0 {
            var minPenalty = Int.max
            for m in 0..<8 {
                applyMask(m)
                drawFormatBits(m)
                let penalty = penaltyScore()
                if penalty < minPenalty {
                    chosen = m
                    minPenalty = penalty
                }
                applyMask(m) // XOR undo
            }
        }
        self.mask = chosen
        applyMask(chosen)
        drawFormatBits(chosen)
        isFunction = []
    }

    // MARK: Function patterns

    private mutating func drawFunctionPatterns() {
        for i in 0..<size {
            setFunction(6, i, i % 2 == 0)
            setFunction(i, 6, i % 2 == 0)
        }
        drawFinder(3, 3)
        drawFinder(size - 4, 3)
        drawFinder(3, size - 4)

        let positions = alignmentPositions()
        let n = positions.count
        for i in 0..<n {
            for j in 0..<n {
                if (i == 0 && j == 0) || (i == 0 && j == n - 1) || (i == n - 1 && j == 0) { continue }
                drawAlignment(positions[i], positions[j])
            }
        }
        drawFormatBits(0)
        drawVersion()
    }

    private mutating func drawFormatBits(_ mask: Int) {
        let data = ecc.formatBits << 3 | mask
        var rem = data
        for _ in 0..<10 { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
        let bits = (data << 10 | rem) ^ 0x5412

        for i in 0...5 { setFunction(8, i, bit(bits, i)) }
        setFunction(8, 7, bit(bits, 6))
        setFunction(8, 8, bit(bits, 7))
        setFunction(7, 8, bit(bits, 8))
        for i in 9..<15 { setFunction(14 - i, 8, bit(bits, i)) }

        for i in 0..<8 { setFunction(size - 1 - i, 8, bit(bits, i)) }
        for i in 8..<15 { setFunction(8, size - 15 + i, bit(bits, i)) }
        setFunction(8, size - 8, true)
    }

    private mutating func drawVersion() {
        guard version >= 7 else { return }
        var rem = version
        for _ in 0..<12 { rem = (rem << 1) ^ ((rem >> 11) * 0x1F25) }
        let bits = version << 12 | rem
        for i in 0..<18 {
            let b = bit(bits, i)
            let a = size - 11 + i % 3
            let c = i / 3
            setFunction(a, c, b)
            setFunction(c, a, b)
        }
    }

    private mutating func drawFinder(_ x: Int, _ y: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                let dist = max(abs(dx), abs(dy))
                let xx = x + dx, yy = y + dy
                if xx >= 0, xx < size, yy >= 0, yy < size {
                    setFunction(xx, yy, dist != 2 && dist != 4)
                }
            }
        }
    }

    private mutating func drawAlignment(_ x: Int, _ y: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                setFunction(x + dx, y + dy, max(abs(dx), abs(dy)) != 1)
            }
        }
    }

    private mutating func setFunction(_ x: Int, _ y: Int, _ dark: Bool) {
        modules[y][x] = dark
        isFunction[y][x] = true
    }

    private func alignmentPositions() -> [Int] {
        guard version > 1 else { return [] }
        let n = version / 7 + 2
        let step = (version * 8 + n * 3 + 5) / (n * 4 - 4) * 2
        var result = [Int](repeating: 0, count: n)
        result[0] = 6
        var pos = size - 7
        var i = n - 1
        while i >= 1 {
            result[i] = pos
            i -= 1
            pos -= step
        }
        return result
    }

    // MARK: Codewords

    private func addEccAndInterleave(_ data: [UInt8]) -> [UInt8] {
        let numBlocks = QRCode.numBlocks[ecc.rawValue][version]
        let blockEccLen = QRCode.eccPerBlock[ecc.rawValue][version]
        let rawCodewords = QRCode.numRawDataModules(version: version) / 8
        let numShortBlocks = numBlocks - rawCodewords % numBlocks
        let shortBlockLen = rawCodewords / numBlocks

        let divisor = QRCode.rsDivisor(degree: blockEccLen)
        var blocks: [[UInt8]] = []
        var k = 0
        for i in 0..<numBlocks {
            let len = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1)
            let dat = Array(data[k..<(k + len)])
            k += len
            var block = dat + [UInt8](repeating: 0, count: shortBlockLen + 1 - dat.count)
            let ecc = QRCode.rsRemainder(dat, divisor: divisor)
            for (j, e) in ecc.enumerated() { block[block.count - blockEccLen + j] = e }
            blocks.append(block)
        }

        var result: [UInt8] = []
        result.reserveCapacity(rawCodewords)
        for i in 0..<blocks[0].count {
            for j in 0..<blocks.count where i != shortBlockLen - blockEccLen || j >= numShortBlocks {
                result.append(blocks[j][i])
            }
        }
        return result
    }

    private mutating func drawCodewords(_ data: [UInt8]) {
        var i = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vert in 0..<size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = ((right + 1) & 2) == 0
                    let y = upward ? size - 1 - vert : vert
                    if !isFunction[y][x] && i < data.count * 8 {
                        modules[y][x] = bit(Int(data[i >> 3]), 7 - (i & 7))
                        i += 1
                    }
                }
            }
            right -= 2
        }
    }

    private mutating func applyMask(_ mask: Int) {
        for y in 0..<size {
            for x in 0..<size {
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (x / 3 + y / 2) % 2 == 0
                case 5: invert = x * y % 2 + x * y % 3 == 0
                case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                }
                if invert && !isFunction[y][x] { modules[y][x].toggle() }
            }
        }
    }

    // MARK: Penalty

    private func penaltyScore() -> Int {
        var result = 0
        for y in 0..<size {
            var runColor = false, run = 0
            var history = [Int](repeating: 0, count: 7)
            for x in 0..<size {
                if modules[y][x] == runColor {
                    run += 1
                    if run == 5 { result += 3 } else if run > 5 { result += 1 }
                } else {
                    addHistory(run, &history)
                    if !runColor { result += countPatterns(history) * 40 }
                    runColor = modules[y][x]
                    run = 1
                }
            }
            result += terminateAndCount(runColor, run, &history) * 40
        }
        for x in 0..<size {
            var runColor = false, run = 0
            var history = [Int](repeating: 0, count: 7)
            for y in 0..<size {
                if modules[y][x] == runColor {
                    run += 1
                    if run == 5 { result += 3 } else if run > 5 { result += 1 }
                } else {
                    addHistory(run, &history)
                    if !runColor { result += countPatterns(history) * 40 }
                    runColor = modules[y][x]
                    run = 1
                }
            }
            result += terminateAndCount(runColor, run, &history) * 40
        }
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let c = modules[y][x]
                if c == modules[y][x + 1] && c == modules[y + 1][x] && c == modules[y + 1][x + 1] {
                    result += 3
                }
            }
        }
        let dark = modules.reduce(0) { $0 + $1.filter { $0 }.count }
        let total = size * size
        let k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        result += k * 10
        return result
    }

    private func countPatterns(_ h: [Int]) -> Int {
        let n = h[1]
        let core = n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n
        return (core && h[0] >= n * 4 && h[6] >= n ? 1 : 0) + (core && h[6] >= n * 4 && h[0] >= n ? 1 : 0)
    }

    private func terminateAndCount(_ color: Bool, _ length: Int, _ history: inout [Int]) -> Int {
        var length = length
        if color {
            addHistory(length, &history)
            length = 0
        }
        length += size
        addHistory(length, &history)
        return countPatterns(history)
    }

    private func addHistory(_ length: Int, _ history: inout [Int]) {
        var length = length
        if history[0] == 0 { length += size }
        for i in stride(from: history.count - 1, to: 0, by: -1) { history[i] = history[i - 1] }
        history[0] = length
    }

    // MARK: Helpers

    private func bit(_ x: Int, _ i: Int) -> Bool { (x >> i) & 1 != 0 }

    private static func charCountBits(version: Int) -> Int { version <= 9 ? 8 : 16 }

    private static func numRawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let n = version / 7 + 2
            result -= (25 * n - 10) * n - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }

    private static func numDataCodewords(version: Int, ecc: ECC) -> Int {
        numRawDataModules(version: version) / 8 - eccPerBlock[ecc.rawValue][version] * numBlocks[ecc.rawValue][version]
    }

    private static func rsDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = rsMultiply(result[j], root)
                if j + 1 < degree { result[j] ^= result[j + 1] }
            }
            root = rsMultiply(root, 0x02)
        }
        return result
    }

    private static func rsRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for b in data {
            let factor = b ^ result[0]
            result.removeFirst()
            result.append(0)
            for i in 0..<result.count { result[i] ^= rsMultiply(divisor[i], factor) }
        }
        return result
    }

    private static func rsMultiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        let x = Int(x), y = Int(y)
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((y >> i) & 1) * x
        }
        return UInt8(z & 0xFF)
    }

    private static let eccPerBlock: [[Int]] = [
        [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
        [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    ]

    private static let numBlocks: [[Int]] = [
        [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
        [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
        [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
        [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
    ]
}

private struct BitBuffer {
    var bits: [Bool] = []
    var count: Int { bits.count }

    mutating func append(_ value: Int, count: Int) {
        guard count > 0 else { return }
        for i in stride(from: count - 1, through: 0, by: -1) {
            bits.append((value >> i) & 1 != 0)
        }
    }
}
