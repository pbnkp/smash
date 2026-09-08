import SwiftUI
import SmashKit
import UniformTypeIdentifiers

@main
struct SmashiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ArtifactView()
        }
    }
}

/// What the app was able to work out about an opened artifact.
struct Inspection {
    var manifest: SmashManifest
    var chain: SmashChain?
    /// Restored bytes, when the chain is one iOS can invert unaided.
    var restored: Data?
    /// Whether the restored bytes matched the sha256 in the manifest.
    var digestMatches: Bool?
    var error: String?
}

struct ArtifactView: View {
    @State private var importing = false
    @State private var inspection: Inspection?
    @State private var filename: String?

    var body: some View {
        NavigationStack {
            Group {
                if let inspection {
                    ArtifactDetail(inspection: inspection, filename: filename ?? "artifact")
                } else {
                    empty
                }
            }
            .navigationTitle("Smash")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Open") { importing = true }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.plainText, .text, .data],
                          allowsMultipleSelection: false) { result in
                handle(result)
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No artifact open", systemImage: "shippingbox")
        } description: {
            Text("Open a .smash.txt file to inspect what it contains and where it came from.")
        } actions: {
            Button("Open Artifact") { importing = true }.buttonStyle(.borderedProminent)
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            inspection = Inspection(manifest: SmashManifest(), chain: nil, error: e.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            filename = url.lastPathComponent
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                inspection = Self.inspect(text)
            } catch {
                inspection = Inspection(manifest: SmashManifest(), chain: nil,
                                        error: "Could not read the file: \(error.localizedDescription)")
            }
        }
    }

    /// Parse, then decode if -- and only if -- this platform can actually
    /// invert the chain. When it cannot, the artifact is still fully readable
    /// as provenance, and the reason is stated instead of a generic failure.
    static func inspect(_ text: String) -> Inspection {
        let manifest = SmashManifest.parse(text)
        guard let chain = manifest.chain else {
            return Inspection(manifest: manifest, chain: nil,
                              error: "This file has no smash manifest; it may not be an artifact.")
        }
        guard chain.nativeDecodeBlocker == nil else {
            return Inspection(manifest: manifest, chain: chain)
        }
        do {
            let payload = SmashPayload.stripManifest(text)
            let compressed = try SmashPayload.decodeAlphabet(payload, chain.alphabet)
            let bytes = try SmashPayload.gunzip(compressed)
            let matches = manifest.sourceSHA256.map { $0 == SmashDigest.sha256Hex(bytes) }
            return Inspection(manifest: manifest, chain: chain, restored: bytes, digestMatches: matches)
        } catch {
            return Inspection(manifest: manifest, chain: chain, error: String(describing: error))
        }
    }
}
