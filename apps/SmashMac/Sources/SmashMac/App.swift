import SwiftUI
import SmashKit
import UniformTypeIdentifiers

final class SmashWindowDelegate: NSObject, NSApplicationDelegate {
    var openFiles: (([URL]) -> Void)?
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openFiles {
            openFiles(urls)
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func bind(_ handler: @escaping ([URL]) -> Void) {
        openFiles = handler
        if !pending.isEmpty {
            let batch = pending
            pending = []
            handler(batch)
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
                .onAppear { windowDelegate.bind { model.accept(urls: $0) } }
                .onChange(of: model.portableGzip) { _, _ in model.persist() }
                .onChange(of: model.redact) { _, _ in model.persist() }
                .onChange(of: model.encrypt) { _, _ in model.persist() }
                .onChange(of: model.recordHost) { _, _ in model.persist() }
                .onChange(of: model.smashFolder) { _, _ in model.persist() }
                .onChange(of: model.revealWhenDone) { _, _ in model.persist() }
                .onChange(of: model.originLabel) { _, _ in model.persist() }
        }
        .defaultSize(width: 560, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.pickFiles() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            MacSettings().environmentObject(model)
        }

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
            Button("Open…") { model.pickFiles() }
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
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
                Button("Open…") { model.pickFiles() }
                Toggle("Portable", isOn: $model.portableGzip)
                    .help("Force the gzip chain, the one format the iOS app can open unaided.")
                Toggle("Redact", isOn: $model.redact)
                    .help("Strip credential values before encoding. Not byte-identical on restore.")
                Toggle("Encrypt", isOn: $model.encrypt)
                    .help("Encrypt with the age key already on this Mac. Smash does not make a key.")
                Button("Clear") { model.clearFinished() }
                    .disabled(model.jobs.allSatisfy { if case .pending = $0.outcome { return true }; return false })
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
            Text("smash v6 was not found. Install it, or put the v6 binary on this Mac.")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.18))
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
            .foregroundStyle(targeted ? Color(red: 0.22, green: 0.74, blue: 0.97) : Color.secondary.opacity(0.45))
            .frame(height: 130)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26))
                    Text("Drop files or folders to smash")
                    Text("Drop a .smash.txt artifact to restore it")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Settings chooses the chain, the folder, and what the manifest records.")
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
            if let url = job.resultURL {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.borderless)
            }
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

struct MacSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Portable gzip", isOn: $model.portableGzip)
                Text("The gzip chain is the one the iPhone app can restore. Other chains stay smaller and still open on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Redact credentials", isOn: $model.redact)
                Text("Values are stripped before encoding. The restore is not byte-identical, and the manifest says so.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Encrypt with age", isOn: $model.encrypt)
                Text("Uses the age key this Mac already has. Smash does not create a key.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Encode")
            }

            Section {
                Toggle("Record this Mac's short name", isOn: $model.recordHost)
                TextField("Origin label", text: $model.originLabel)
                Text("Leave both alone and the artifact does not say which machine made it or where it came from.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }

            Section {
                Toggle("Write into the Smash folder", isOn: $model.smashFolder)
                Text(model.smashFolder
                     ? "New artifacts go in the Smash folder in your home directory."
                     : "New artifacts are written next to the file you dropped.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reveal in Finder when finished", isOn: $model.revealWhenDone)
            } header: {
                Text("Output")
            }

            Section {
                LabeledContent("Engine") {
                    Text(model.cliVersion ?? "smash v6 was not found")
                }
                if let path = model.cliPath {
                    LabeledContent("Binary") {
                        Text(Self.enginePlace(path))
                    }
                }
            } header: {
                Text("This Mac")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(12)
    }

    private static func enginePlace(_ path: String) -> String {
        if path.contains("/opt/homebrew/") { return "Homebrew" }
        if path.contains("/.local/bin/") { return "Home binary" }
        if path.hasSuffix("/bin/smash") { return "Home binary" }
        return "Installed binary"
    }
}
