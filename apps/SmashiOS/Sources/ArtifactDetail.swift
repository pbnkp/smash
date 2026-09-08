import SwiftUI
import SmashKit
import UniformTypeIdentifiers

struct ArtifactDetail: View {
    let inspection: Inspection
    let filename: String

    private var m: SmashManifest { inspection.manifest }

    var body: some View {
        List {
            if let error = inspection.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            // The honesty section. An artifact that does not restore
            // byte-identically says so here, in the words the manifest used,
            // rather than letting someone discover it by a sha mismatch later.
            if let why = m.lossyExplanation {
                Section("Not byte-identical") {
                    Label(why, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Source") {
                row("Name", m.source ?? filename)
                if let kind = m.kind { row("Kind", kind) }
                if let bytes = m.sourceBytes {
                    row("Size", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                }
                if let origin = m.origin { row("Origin", origin) }
                if let created = m.created { row("Created", created) }
                if let host = m.host { row("Host", host) }
            }

            Section("Encoding") {
                if let chain = inspection.chain {
                    row("Chain", chain.displayPath)
                    row("Engine", chain.isSuperposition ? "superposition (v6.0)" : "classic")
                }
                if let v = m.toolVersion { row("Written by", "smash v\(v)") }
                if let c = m.cipher {
                    row("Encrypted", c)
                    if let r = m.recipient { row("Recipient", String(r.prefix(24)) + "…") }
                }
            }

            if let sha = m.sourceSHA256 {
                Section("Integrity") {
                    row("Source sha256", String(sha.prefix(24)) + "…")
                    if let matches = inspection.digestMatches {
                        Label(
                            matches ? "Restored bytes match the recorded sha256."
                                    : "Restored bytes do NOT match the recorded sha256.",
                            systemImage: matches ? "checkmark.seal.fill" : "xmark.seal.fill"
                        )
                        .foregroundStyle(matches ? .green : .red)
                    }
                }
            }

            Section("Restore") {
                if let data = inspection.restored {
                    Label("Restored \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) on device.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let preview = String(data: data.prefix(4096), encoding: .utf8), !preview.isEmpty {
                        NavigationLink("Preview contents") { TextPreview(text: preview) }
                    }
                    ShareLink(item: SavedFile(data: data, name: m.source ?? "restored"),
                              preview: SharePreview(m.source ?? "restored")) {
                        Label("Save or Share restored file", systemImage: "square.and.arrow.up")
                    }
                } else if let blocker = inspection.chain?.nativeDecodeBlocker {
                    Label(blocker, systemImage: "lock.circle")
                        .foregroundStyle(.secondary)
                    Text("Re-encode with `smash -g` on the desktop to produce an artifact this app can restore.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.callout.monospaced()).multilineTextAlignment(.trailing)
        }
    }
}

struct TextPreview: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text).font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Preview")
    }
}

/// Wraps restored bytes so ShareLink can hand them to Files, Mail, anywhere.
struct SavedFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { $0.data }
            .suggestedFileName { $0.name }
    }
}
