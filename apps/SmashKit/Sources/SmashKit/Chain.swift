import Foundation

/// The decode chain an artifact declares, parsed from its `encoding:` line.
///
/// smash writes the chain outermost-first, e.g.
///     sp-v1( base85( brotli( tsv1( source ) ) ) )
///     base64( xz( source ) )
///     b85( xz( jxl( source ) ) )              // the 5.6/5.7 line
/// so inverting means: strip the alphabet, run the codec's decompressor, then
/// undo the transform. This type models exactly that, and -- importantly --
/// knows which steps a given platform can actually perform.
public struct SmashChain: Sendable, Equatable {

    public enum Alphabet: String, Sendable {
        case base64, base85
    }

    public enum Codec: String, Sendable {
        case xz, brotli, zstd, gzip, lzma
    }

    public enum Transform: String, Sendable {
        /// Column-major transposition of uniform delimited records.
        case tsv1
        /// Lossless JPEG bitstream transcode; inverse needs `djxl`.
        case jxl
        /// Deliberate lossy JPEG re-encode; has no inverse at all.
        case jpegFit
        case none
    }

    public var alphabet: Alphabet
    public var codec: Codec
    public var transform: Transform
    /// True when the artifact carries the v6.0 `sp-v1(` marker.
    public var isSuperposition: Bool
    /// The expression exactly as written in the manifest.
    public var expression: String

    public init(expression: String) {
        self.expression = expression
        let e = expression

        isSuperposition = e.contains("sp-v1(")

        if e.contains("base85(") || e.contains("b85(") {
            alphabet = .base85
        } else {
            alphabet = .base64
        }

        if e.contains("brotli(")      { codec = .brotli }
        else if e.contains("zstd(") || e.contains("zst(") { codec = .zstd }
        else if e.contains("gzip(") || e.contains("gz(")  { codec = .gzip }
        else if e.contains("xz(")     { codec = .xz }
        else                          { codec = .xz }

        if e.contains("tsv1(")        { transform = .tsv1 }
        else if e.contains("jpeg-fit(") { transform = .jpegFit }
        else if e.contains("jxl(")    { transform = .jxl }
        else                          { transform = .none }
    }
}

extension SmashChain {
    /// Why this chain cannot be inverted natively on the current platform,
    /// or nil when it can.
    ///
    /// The point of naming the specific missing capability is that a user who
    /// gets "needs brotli" can act on it, whereas "decode failed" tells them
    /// nothing about whether the file or the app is at fault.
    public var nativeDecodeBlocker: String? {
        if transform == .jpegFit {
            return "This artifact is a deliberate quality trade and has no inverse; it already contains the fitted image."
        }
        if transform == .jxl {
            return "The jxl stage needs the JPEG XL decoder (djxl), which is not available in-app."
        }
        switch codec {
        case .gzip: return nil          // handled natively via Compression
        case .xz:   return "The xz container is not decodable in-app; use the desktop tool."
        case .brotli: return "This artifact uses brotli, which is not available in-app."
        case .zstd: return "This artifact uses zstd, which is not available in-app."
        case .lzma: return "Raw LZMA artifacts are not supported in-app."
        }
    }

    /// Human-facing one-liner for the chain, e.g. "base85 → brotli → tsv1".
    public var displayPath: String {
        var parts: [String] = [alphabet.rawValue, codec.rawValue]
        if transform != .none { parts.append(transform.rawValue) }
        return parts.joined(separator: " → ")
    }
}
