import SwiftUI

extension String {
    func containsBytes(_ needle: StaticString) -> Bool {
        needle.withUTF8Buffer { pattern in
            utf8.withContiguousStorageIfAvailable { Self.search(pattern, in: $0) }
                ?? Array(utf8).withUnsafeBufferPointer { Self.search(pattern, in: $0) }
        }
    }

    func containsAnyByte(_ bytes: StaticString) -> Bool {
        bytes.withUTF8Buffer { set in utf8.contains { set.contains($0) } }
    }

    private static func search(_ pattern: UnsafeBufferPointer<UInt8>, in hay: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let first = pattern.first else { return true }
        guard hay.count >= pattern.count else { return false }
        let last = hay.count - pattern.count
        var i = 0
        while i <= last {
            if hay[i] == first {
                var j = 1
                while j < pattern.count, hay[i + j] == pattern[j] { j += 1 }
                if j == pattern.count { return true }
            }
            i += 1
        }
        return false
    }
}

extension Array where Element == UInt8 {
    func has(_ s: StaticString, at i: Int) -> Bool {
        s.withUTF8Buffer { has($0, at: i) }
    }

    func has<C: Collection>(_ s: C, at i: Int) -> Bool where C.Element == UInt8 {
        guard i >= 0, i + s.count <= count else { return false }
        var k = i
        for byte in s {
            if self[k] != byte { return false }
            k += 1
        }
        return true
    }

    func find(_ s: StaticString, from: Int) -> Int? {
        s.withUTF8Buffer { find($0, from: from) }
    }

    func find<C: Collection>(_ s: C, from: Int) -> Int? where C.Element == UInt8 {
        guard from <= count else { return nil }
        var i = from
        while i < count {
            if has(s, at: i) { return i }
            i += 1
        }
        return nil
    }
}

extension Array where Element == Character {
    func has(_ s: String, at i: Int) -> Bool {
        var k = i
        for ch in s {
            guard k < count, self[k] == ch else { return false }
            k += 1
        }
        return true
    }

    func find(_ s: String, from: Int) -> Int? {
        guard from <= count else { return nil }
        var i = from
        while i < count {
            if has(s, at: i) { return i }
            i += 1
        }
        return nil
    }
}
