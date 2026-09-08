import Foundation

/// Everything a smash artifact declares about itself, parsed from the
/// `# `-prefixed manifest that precedes the payload.
///
/// The manifest is the contract: an artifact is self-describing, so a reader
/// never has to guess how it was made. Parsing is deliberately tolerant --
/// unknown fields are ignored and missing optional fields stay nil, so an
/// artifact written by a NEWER smash still yields everything this build
/// understands instead of failing wholesale.
public struct SmashManifest: Sendable, Equatable {
    /// Version stamped by the tool that wrote the artifact, e.g. "6.0".
    public var toolVersion: String?
    /// UTC timestamp string, as written.
    public var created: String?
    /// Host that produced it.
    public var host: String?
    /// Original path/label of the source.
    public var source: String?
    /// "file", "dir-tar", "stdin", "string", ...
    public var kind: String?
    /// Size of the ORIGINAL source in bytes.
    public var sourceBytes: Int?
    /// sha256 of the ORIGINAL source.
    public var sourceSHA256: String?
    /// Free-text provenance, when `--origin` was passed.
    public var origin: String?
    /// Cipher name when the payload is encrypted, e.g. "age".
    public var cipher: String?
    /// age recipient, when present.
    public var recipient: String?
    /// The raw encoding expression, e.g. `sp-v1( base85( brotli( tsv1( source ) ) ) )`.
    public var encodingExpression: String?
    /// Value of the `lossy:` field: "no", "yes", "redacted", "visual-fit".
    public var lossy: String?
    /// True when the manifest carries the redaction notice.
    public var isRedacted: Bool = false
    /// JPEG quality recorded by `--fit`.
    public var fitQuality: Int?
    /// sha256 of the fitted payload (NOT the original) when `--fit` was used.
    public var fitSHA256: String?
    /// Alphabet named by the PAYLOAD banner: "base64" or "base85".
    public var payloadAlphabet: String?

    public init() {}

    /// The decode chain implied by `encodingExpression`.
    public var chain: SmashChain? {
        encodingExpression.map(SmashChain.init(expression:))
    }

    /// Whether restoring this artifact yields bytes identical to the source.
    /// False for `--ai`, `--redact` and `--fit` artifacts, which say so
    /// themselves rather than leaving a caller to discover it by mismatch.
    public var restoresByteIdentical: Bool {
        switch lossy {
        case .some("no"), .none: return !isRedacted
        default: return false
        }
    }

    /// A one-line, human-facing reason when the artifact is NOT byte-identical.
    public var lossyExplanation: String? {
        guard !restoresByteIdentical else { return nil }
        switch lossy {
        case .some("redacted"):
            return "Credential values were stripped before encoding. Restores to the redacted text, not the original. A sha256 mismatch is correct."
        case .some("visual-fit"):
            let q = fitQuality.map { " (JPEG quality \($0))" } ?? ""
            return "Deliberate quality trade\(q). Restores to a visually equivalent image, not the original bytes."
        case .some("yes"):
            return "Semantically compacted with --ai. Restores to compacted text, not the original bytes."
        default:
            return "This artifact does not restore byte-identically."
        }
    }
}

extension SmashManifest {
    /// Parse the manifest out of full artifact text.
    ///
    /// Only the leading `#` lines are inspected, so this is cheap even on a
    /// very large artifact when the caller passes just the head of the file.
    public static func parse(_ text: String) -> SmashManifest {
        var m = SmashManifest()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard rawLine.hasPrefix("#") else {
                // Payload reached; nothing below is manifest.
                if !rawLine.isEmpty { break }
                continue
            }
            let line = rawLine.dropFirst().trimmingCharacters(in: .whitespaces)

            if let v = line.captureAfter("tool: smash v") {
                m.toolVersion = v.prefix(while: { !$0.isWhitespace }).description
            }
            if line.hasPrefix("created:") {
                let parts = line.dropFirst("created:".count).components(separatedBy: "| host:")
                m.created = parts.first?.trimmingCharacters(in: .whitespaces)
                if parts.count > 1 { m.host = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            if line.hasPrefix("source:") {
                let fields = line.pipeFields()
                m.source = fields["source"]
                m.kind = fields["kind"]
                m.sourceBytes = fields["bytes"].flatMap(Int.init)
                m.sourceSHA256 = fields["sha256"]
            }
            if line.hasPrefix("origin:") {
                let v = line.dropFirst("origin:".count).trimmingCharacters(in: .whitespaces)
                m.origin = v.hasPrefix("unrecorded") ? nil : v
            }
            if line.hasPrefix("cipher:") {
                let fields = line.pipeFields()
                m.cipher = fields["cipher"]
                m.recipient = fields["recipient"]
            }
            if line.hasPrefix("encoding:") {
                let body = line.dropFirst("encoding:".count)
                let parts = body.components(separatedBy: "| lossy:")
                m.encodingExpression = parts.first?.trimmingCharacters(in: .whitespaces)
                if parts.count > 1 { m.lossy = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            if line.hasPrefix("redacted:") { m.isRedacted = true }
            if line.hasPrefix("fit:") {
                let fields = line.pipeFields()
                if let raw = fields["fit"] {
                    let digits = raw.replacingOccurrences(of: "jpeg q=", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    m.fitQuality = Int(digits)
                }
                m.fitSHA256 = fields["fit-sha256"]
            }
            if let a = line.captureAfter("==== PAYLOAD (") {
                m.payloadAlphabet = a.prefix(while: { $0 != ")" }).description
            }
        }
        return m
    }
}

// MARK: - small parsing helpers

extension StringProtocol {
    fileprivate func trimmed() -> String {
        trimmingCharacters(in: .whitespaces)
    }

    fileprivate func captureAfter(_ needle: String) -> String? {
        guard let r = range(of: needle) else { return nil }
        return String(self[r.upperBound...])
    }

    /// Split a `a: 1 | b: 2 | c: 3` line into a dictionary.
    fileprivate func pipeFields() -> [String: String] {
        var out: [String: String] = [:]
        for field in components(separatedBy: "|") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].trimmed()
            let value = field[field.index(after: colon)...].trimmed()
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}
