import Foundation
import Compression

/// Decoding of the parts of an artifact that need no external binaries.
///
/// smash armours every payload as printable ASCII so an artifact survives
/// being pasted into a chat window or an LLM context. Undoing that armour is
/// pure arithmetic, so it works identically on macOS and iOS with no
/// dependencies at all. The compressed layer underneath is where platform
/// capability actually starts to matter.
public enum SmashPayload {

    public enum Failure: Error, CustomStringConvertible {
        case badAlphabet(String)
        case truncated
        case notGzip
        case inflateFailed

        public var description: String {
            switch self {
            case .badAlphabet(let c): return "Payload contains a character not in the expected alphabet: \(c)"
            case .truncated:          return "Payload is truncated."
            case .notGzip:            return "Stream is not gzip-framed."
            case .inflateFailed:      return "Decompression failed; the payload is corrupt or clipped."
            }
        }
    }

    /// Strip the manifest and all whitespace, leaving bare payload text.
    ///
    /// Matching the CLI, `#` lines are dropped BY CONTENT rather than by
    /// position, so an artifact with a trailing manifest (the streaming sink
    /// path writes one) is handled by the same code.
    public static func stripManifest(_ artifact: String) -> String {
        artifact
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("#") }
            .joined()
            .filter { !$0.isWhitespace }
    }

    // MARK: - Alphabets

    /// RFC 1924 alphabet, matching Python's `base64.b85encode`, which is what
    /// smash uses to write base85 payloads.
    private static let b85Alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"
    )
    private static let b85Reverse: [Int8] = {
        var t = [Int8](repeating: -1, count: 128)
        for (i, ch) in b85Alphabet.enumerated() {
            if let a = ch.asciiValue { t[Int(a)] = Int8(i) }
        }
        return t
    }()

    public static func decodeBase85(_ text: String) throws -> Data {
        var out = Data()
        out.reserveCapacity(text.utf8.count * 4 / 5 + 4)
        var group: [UInt32] = []
        group.reserveCapacity(5)

        for ch in text.utf8 {
            guard ch < 128, b85Reverse[Int(ch)] >= 0 else {
                throw Failure.badAlphabet(String(UnicodeScalar(ch)))
            }
            group.append(UInt32(b85Reverse[Int(ch)]))
            if group.count == 5 {
                var acc: UInt32 = 0
                for d in group { acc = acc &* 85 &+ d }
                out.append(contentsOf: [
                    UInt8(truncatingIfNeeded: acc >> 24),
                    UInt8(truncatingIfNeeded: acc >> 16),
                    UInt8(truncatingIfNeeded: acc >> 8),
                    UInt8(truncatingIfNeeded: acc),
                ])
                group.removeAll(keepingCapacity: true)
            }
        }

        // A partial trailing group encodes (count - 1) bytes; pad with the
        // highest digit so the arithmetic lands on the same value the encoder
        // started from, then keep only the bytes that were really there.
        if !group.isEmpty {
            guard group.count > 1 else { throw Failure.truncated }
            let real = group.count - 1
            var padded = group
            while padded.count < 5 { padded.append(84) }
            var acc: UInt32 = 0
            for d in padded { acc = acc &* 85 &+ d }
            let bytes = [
                UInt8(truncatingIfNeeded: acc >> 24),
                UInt8(truncatingIfNeeded: acc >> 16),
                UInt8(truncatingIfNeeded: acc >> 8),
                UInt8(truncatingIfNeeded: acc),
            ]
            out.append(contentsOf: bytes.prefix(real))
        }
        return out
    }

    public static func decodeBase64(_ text: String) throws -> Data {
        guard let d = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) else {
            throw Failure.truncated
        }
        return d
    }

    public static func decodeAlphabet(_ text: String, _ alphabet: SmashChain.Alphabet) throws -> Data {
        switch alphabet {
        case .base64: return try decodeBase64(text)
        case .base85: return try decodeBase85(text)
        }
    }

    // MARK: - gzip

    /// Inflate a gzip stream using Apple's Compression framework.
    ///
    /// Compression exposes raw DEFLATE, not gzip, so the 10-byte header and
    /// its optional fields are parsed here and the 8-byte trailer ignored.
    /// This is the one compressed format both Apple platforms can invert with
    /// no third-party code, which is what makes `smash -g` artifacts openable
    /// on iPhone.
    public static func gunzip(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 0x08 else {
            throw Failure.notGzip
        }
        let flg = b[3]
        var i = 10
        if flg & 0x04 != 0 {                                   // FEXTRA
            guard i + 1 < b.count else { throw Failure.truncated }
            let xlen = Int(b[i]) | Int(b[i + 1]) << 8
            i += 2 + xlen
        }
        if flg & 0x08 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }  // FNAME
        if flg & 0x10 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }  // FCOMMENT
        if flg & 0x02 != 0 { i += 2 }                                           // FHCRC
        guard i < b.count - 8 else { throw Failure.truncated }

        let deflate = Data(b[i..<(b.count - 8)])
        let expected = Int(UInt32(b[b.count - 4]) | UInt32(b[b.count - 3]) << 8
                         | UInt32(b[b.count - 2]) << 16 | UInt32(b[b.count - 1]) << 24)
        // ISIZE is mod 2^32; give small files an exact buffer and large ones room.
        let capacity = max(expected, 1) + 4096

        var out = Data(count: capacity)
        let produced: Int = out.withUnsafeMutableBytes { dst -> Int in
            deflate.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, capacity, s, deflate.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard produced > 0 else { throw Failure.inflateFailed }
        return out.prefix(produced)
    }
}
