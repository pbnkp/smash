import SwiftUI
import SmashKit
import UniformTypeIdentifiers

final class SmashWindowDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct SmashMacApp: App {
    @NSApplicationDelegateAdaptor(SmashWindowDelegate.self) var windowDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Smash") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 560, height: 680)

        // The menubar icon. Drop-free quick access: toggle the options that
        // change what the next drop produces, and see which CLI is backing
        // the app without opening the window.
        MenuBarExtra("Smash", systemImage: "shippingbox") {
            if model.cliMissing {
                Text("smash CLI not found").foregroundStyle(.secondary)
                Text("brew install pbnkp/smash/smash")
            } else {
                Text(model.cliVersion ?? "smash")
                Divider()
                Toggle("Portable (gzip, opens on iPhone)", isOn: $model.portableGzip)
                Toggle("Redact credentials", isOn: $model.redact)
                Toggle("Encrypt (age)", isOn: $model.encrypt)
            }
            Divider()
            Button("Open Smash") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeKey {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.cliMissing { missingBanner }

            SmashPlay()
                .padding(.horizontal, 16)
                .padding(.top, 12)
            Text(engineLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            dropZone
                .padding(16)

            Divider()

            List(model.jobs) { job in
                JobRow(job: job)
            }
            .listStyle(.inset)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("Portable", isOn: $model.portableGzip)
                    .help("Force the gzip chain, the one format the iOS app can open unaided.")
                Toggle("Redact", isOn: $model.redact)
                    .help("Strip credential values before encoding. Not byte-identical on restore.")
                Toggle("Encrypt", isOn: $model.encrypt)
                    .help("Encrypt the compressed stream with age.")
            }
        }
    }

    private var engineLine: String {
        if let version = model.cliVersion, version.contains("v6") {
            return version
        }
        return "smash v6 was not found"
    }

    private var missingBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("smash v6 was not found. This window runs ~/bin/smash, which is v6.1.")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.18))
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.45))
            .frame(height: 130)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26))
                    Text("Drop files or folders to smash")
                    Text("Drop a .smash.txt artifact to restore it")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                Task {
                    var urls: [URL] = []
                    for p in providers {
                        if let url = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                           let u = URL(dataRepresentation: url, relativeTo: nil) {
                            urls.append(u)
                        }
                    }
                    if !urls.isEmpty { model.accept(urls: urls) }
                }
                return true
            }
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent).font(.body)
                detail.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            icon
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var detail: some View {
        switch job.outcome {
        case .pending:
            Text("Working…")
        case .encoded(_, let original, let artifact, let chain):
            if original > 0 {
                let pct = Int((Double(original - artifact) / Double(original)) * 100)
                Text("\(format(original)) → \(format(artifact))  (\(pct >= 0 ? "−" : "+")\(abs(pct))%)  ·  \(chain)")
            } else {
                Text(chain)
            }
        case .decoded(let restored):
            Text("Restored \(restored.lastPathComponent)")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var icon: some View {
        switch job.outcome {
        case .pending:   ProgressView().controlSize(.small)
        case .encoded:   Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .decoded:   Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.blue)
        case .failed:    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
