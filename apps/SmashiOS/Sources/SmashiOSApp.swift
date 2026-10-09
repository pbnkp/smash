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
    @State private var showSettings = false
    @State private var inspection: Inspection?
    @State private var filename: String?
    @AppStorage("smash.ios.showFullSHA") private var showFullSHA = false
    @AppStorage("smash.ios.keepRestored") private var keepRestored = true

    var body: some View {
        NavigationStack {
            Group {
                if let inspection {
                    ArtifactDetail(
                        inspection: inspection,
                        filename: filename ?? "artifact",
                        showFullSHA: showFullSHA,
                        keepRestored: keepRestored
                    )
                } else {
                    empty
                }
            }
            .navigationTitle("Smash")
            .toolbarBackground(Color.black, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if inspection != nil {
                        Button("Close") {
                            inspection = nil
                            filename = nil
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open") { importing = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                PhoneSettings(showFullSHA: $showFullSHA, keepRestored: $keepRestored)
            }
            .onOpenURL { url in
                handle(.success([url]))
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.plainText, .text, .data],
                          allowsMultipleSelection: false) { result in
                handle(result)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 18) {
            SmashPlay()
            VStack(alignment: .leading, spacing: 8) {
                Text("Open a portable artifact")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("This phone restores the gzip chain and checks it against the sha256 in the file. Every other chain still shows where it came from, and names the chain it cannot invert.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Artifact") { importing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(red: 0.22, green: 0.74, blue: 0.97))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
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

struct PhoneSettings: View {
    @Binding var showFullSHA: Bool
    @Binding var keepRestored: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This iPhone restores the gzip chain and checks the sha256 in the file. Every other chain still shows where it came from.")
                } header: {
                    Text("Restore")
                }

                Section {
                    Toggle("Show the full checksum", isOn: $showFullSHA)
                    Toggle("Keep restored files on this iPhone", isOn: $keepRestored)
                    Text("Kept files stay in Smash’s folder in the Files app. Sharing still asks you each time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("On this iPhone")
                }

                Section {
                    LabeledContent("Version", value: "6.1")
                    LabeledContent("Engine", value: "SmashKit")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
