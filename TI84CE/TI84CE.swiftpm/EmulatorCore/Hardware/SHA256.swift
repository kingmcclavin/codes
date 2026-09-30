import Foundation

/// SHA-256 compression function and a convenience digest (pure Swift, no CryptoKit,
/// so the core also builds on Linux).
public enum SHA256 {
    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    @inline(__always) static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    /// Processes one 64-byte block given as 16 big-endian message words.
    public static func compress(state h: inout [UInt32], block: [UInt32]) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 { w[i] = block[i] }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
        h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
    }

    public static func digest(_ data: [UInt8]) -> [UInt8] {
        var h = initialState
        var msg = data
        let bitLen = UInt64(data.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8(truncatingIfNeeded: bitLen >> (UInt64(i) * 8))) }
        var block = [UInt32](repeating: 0, count: 16)
        var off = 0
        while off < msg.count {
            for i in 0..<16 {
                let j = off + i * 4
                block[i] = UInt32(msg[j]) << 24 | UInt32(msg[j + 1]) << 16 | UInt32(msg[j + 2]) << 8 | UInt32(msg[j + 3])
            }
            compress(state: &h, block: block)
            off += 64
        }
        return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - UInt32($0) * 8)) } }
    }

    public static func hexDigest(_ data: [UInt8]) -> String {
        digest(data).map { String(format: "%02x", $0) }.joined()
    }
}

/// SHA-256 hardware accelerator (port range 2xxx, memory-mapped at 0xE10000),
/// used by the boot code to verify OS signatures.
///
///     +00 control (W): 0x0A = init + hash block, 0x0E = hash block, 0x10 = clear
///     +10..+4F  16 message words (32-bit, little-endian register access)
///     +60..+7F  8 state words (read)
public final class SHA256Accelerator: IODevice {
    public private(set) var state = [UInt32](repeating: 0, count: 8)
    public private(set) var block = [UInt32](repeating: 0, count: 16)
    private var lastIndex = 0

    public init() {}

    public func reset() {
        state = [UInt32](repeating: 0, count: 8)
        block = [UInt32](repeating: 0, count: 16)
    }

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00..<0x0C: return 0                                // not busy
        case 0x10..<0x50: return byteOf(block[(o - 0x10) >> 2], o)
        case 0x60..<0x80: return byteOf(state[(o - 0x60) >> 2], o)
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x00:
            if value & 0x10 != 0 {
                state = [UInt32](repeating: 0, count: 8)
            } else if value & 0x0E == 0x0A {
                state = SHA256.initialState
                SHA256.compress(state: &state, block: block)
            } else if value & 0x0E == 0x0E {
                SHA256.compress(state: &state, block: block)
            }
        case 0x10..<0x50:
            setByte(&block[(o - 0x10) >> 2], o, value)
        default:
            break
        }
    }

    public struct Snapshot: Codable, Equatable { var state: [UInt32]; var block: [UInt32] }
    public var snapshot: Snapshot {
        get { Snapshot(state: state, block: block) }
        set { state = newValue.state; block = newValue.block }
    }
}
