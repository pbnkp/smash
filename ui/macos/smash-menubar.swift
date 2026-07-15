// smash-menubar — macOS menu-bar UI for smash.
// Sole author: pbnkp. MIT.
//
// Pure AppKit, single file, swiftc-compiled. No SwiftUI, no WebView, no Node.
// The CLI at ~/bin/smash stays the single source of truth — this app is a
// skin: drag anything onto the menu-bar icon (or use the popover) and it
// shells out with argv (never a shell string).
//
// Settings: non-secret prefs in UserDefaults (com.pbnkp.smash).
// API keys: macOS Keychain ONLY (generic password, service com.pbnkp.smash).
// "Use with subscription AI": one click installs/registers the smash-mcp
// network layer with Claude (claude mcp add) — no API key involved.

import AppKit
import Security

let kService = "com.pbnkp.smash"
let ud = UserDefaults(suiteName: kService)!

func home(_ p: String) -> String { (NSHomeDirectory() as NSString).appendingPathComponent(p) }
func smashPath() -> String {
    let cands = [home("bin/smash"), home(".local/bin/smash"), "/opt/homebrew/bin/smash", "/usr/local/bin/smash"]
    for c in cands where FileManager.default.isExecutableFile(atPath: c) { return c }
    return "smash"
}
func mcpPath() -> String {
    let cands = [home("bin/smash-mcp"), home(".local/bin/smash-mcp"),
                 "/opt/homebrew/bin/smash-mcp", "/usr/local/bin/smash-mcp"]
    return cands.first { FileManager.default.isExecutableFile(atPath: $0) } ?? home("bin/smash-mcp")
}

// ---------- Keychain ----------
func keychainSet(_ account: String, _ value: String) -> Bool {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: kService,
                            kSecAttrAccount as String: account]
    SecItemDelete(q as CFDictionary)
    if value.isEmpty { return true }
    var add = q
    add[kSecValueData as String] = value.data(using: .utf8)!
    add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
}
func keychainGet(_ account: String) -> String {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: kService,
                            kSecAttrAccount as String: account,
                            kSecReturnData as String: true,
                            kSecMatchLimit as String: kSecMatchLimitOne]
    var out: CFTypeRef?
    if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
       let d = out as? Data, let s = String(data: d, encoding: .utf8) { return s }
    return ""
}

// ---------- smash runner ----------
struct JobResult { let ok: Bool; let line: String; let artifact: String? }

final class Engine {
    static func run(args: [String], env extra: [String: String] = [:], timeout: TimeInterval = 300) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: smashPath())
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extra { env[k] = v }
        p.environment = env
        let so = Pipe(), se = Pipe()
        p.standardOutput = so; p.standardError = se
        do { try p.run() } catch { return (127, "", "cannot launch smash: \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(timeout)
        DispatchQueue.global().async {
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if p.isRunning { p.terminate() }
        }
        p.waitUntilExit()
        let o = String(data: so.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: se.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, o, e)
    }

    static func aiEnv() -> [String: String] {
        var env: [String: String] = [:]
        switch ud.string(forKey: "provider") ?? "ollama" {
        case "anthropic":
            let key = keychainGet("anthropic")
            if !key.isEmpty { env["ANTHROPIC_API_KEY"] = key }
        case "custom":
            if let u = ud.string(forKey: "aiURL"), !u.isEmpty { env["B64_AI_URL"] = u }
            let key = keychainGet("custom")
            if !key.isEmpty { env["B64_AI_KEY"] = key }
        default: // ollama local
            env["B64_AI_URL"] = ud.string(forKey: "aiURL").flatMap { $0.isEmpty ? nil : $0 }
                ?? "http://localhost:11434/v1/chat/completions"
        }
        if let m = ud.string(forKey: "aiModel"), !m.isEmpty { env["B64_AI_MODEL"] = m }
        return env
    }

    static func process(paths: [String]) -> [JobResult] {
        var results: [JobResult] = []
        let outdir = ud.string(forKey: "outdir") ?? home("smashes")
        try? FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
        let mode = ud.string(forKey: "mode") ?? "xz"

        let artifacts = paths.filter { $0.contains(".b64.") }
        let inputs = paths.filter { !$0.contains(".b64.") }

        if !artifacts.isEmpty {
            let (rc, _, err) = run(args: ["-d", "-o", outdir + "/", "--"] + artifacts)
            for line in err.split(separator: "\n") {
                let s = String(line)
                if let r = s.range(of: "decoded: ") ?? s.range(of: "decoded+extracted: ") {
                    results.append(JobResult(ok: true, line: "restored " + s[r.upperBound...], artifact: String(s[r.upperBound...])))
                }
            }
            if rc != 0 { results.append(JobResult(ok: false, line: "decode failed: " + (err.split(separator: "\n").last.map(String.init) ?? ""), artifact: nil)) }
        }
        if !inputs.isEmpty {
            var args: [String] = []
            var env: [String: String] = [:]
            switch mode {
            case "gz": args.append("-g")
            case "zstd": args.append("-z")
            case "ai": args.append("--ai")
            case "ai-api": args.append("--ai-api"); env = aiEnv()
            default: break
            }
            args += ["-o", outdir + "/", "--"] + inputs
            let (rc, _, err) = run(args: args, env: env)
            for line in err.split(separator: "\n") {
                let s = String(line)
                if let r = s.range(of: "encoded: ") {
                    let art = String(s[r.upperBound...])
                    results.append(JobResult(ok: true, line: (art as NSString).lastPathComponent, artifact: art))
                }
            }
            if rc != 0 { results.append(JobResult(ok: false, line: "smash failed: " + (err.split(separator: "\n").last.map(String.init) ?? ""), artifact: nil)) }
        }
        return results
    }
}

// ---------- drop view over the status button ----------
// This ONE view owns both interactions: a click toggles the popover, a file
// drag encodes/decodes. An earlier version returned nil from hitTest to "pass
// clicks to the button underneath" — but hit-testing also resolves the drag
// destination, so nil silently broke drop delivery. The correct pattern is a
// single view that handles mouseDown (→ onClick) and performDragOperation
// (→ onDrop); we do NOT override hitTest, so the view receives both.
final class DropView: NSView {
    var onDrop: (([String]) -> Void)?
    var onClick: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { layer?.backgroundColor = NSColor.clear.cgColor }
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if urls.isEmpty { return false }
        onDrop?(urls.map { $0.path })
        return true
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Large, discoverable drop target inside the menu popover. It shares the same
// file-URL-only safety boundary as the status-item drop target and doubles as
// a button that opens a file/folder picker.
final class PanelDropZone: NSView {
    var onDrop: (([String]) -> Void)?
    var onPick: (() -> Void)?
    private let label = NSTextField(labelWithString: "Drop files, folders, or artifacts here\n—or click to choose—")

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drop files into Smash or click to choose files")
    }
    required init?(coder: NSCoder) { nil }

    private func highlight(_ active: Bool) {
        layer?.borderWidth = active ? 2 : 1
        layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.16)
                                          : NSColor.controlBackgroundColor.withAlphaComponent(0.45)).cgColor
        label.textColor = active ? .labelColor : .secondaryLabelColor
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        )
        highlight(valid)
        return valid ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { highlight(false) }
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls.map { $0.path })
        return true
    }
    override func mouseDown(with event: NSEvent) { onPick?() }
}

// ---------- app ----------
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var status: NSStatusItem!
    let popover = NSPopover()
    var results: [JobResult] = []
    var resultLabels: [NSTextField] = []

    // controls we re-read
    var modePop = NSPopUpButton()
    var providerPop = NSPopUpButton()
    var urlField = NSTextField()
    var modelField = NSTextField()
    var keyField = NSSecureTextField()
    var outLabel = NSTextField(labelWithString: "")
    var statusLine = NSTextField(labelWithString: "")
    var resultsStack = NSStackView()

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = status.button {
            b.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "smash")
            b.action = #selector(togglePopover)
            b.target = self
            let dv = DropView(frame: b.bounds)
            dv.autoresizingMask = [.width, .height]
            dv.onDrop = { [weak self] paths in self?.handle(paths: paths) }
            dv.onClick = { [weak self] in self?.togglePopover() }
            b.addSubview(dv)
        }
        popover.behavior = .transient
        popover.contentViewController = makeSettingsVC()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        let launchFiles = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
        if !launchFiles.isEmpty {
            DispatchQueue.main.async { self.handle(paths: Array(launchFiles)) }
        }

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showPopover() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter { $0.isFileURL }.map { $0.path }
        if !files.isEmpty { handle(paths: files) }
    }

    @objc func smashFiles(_ pboard: NSPasteboard, userData: String,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "Smash received no file URLs." as NSString
            return
        }
        handle(paths: urls.map { $0.path })
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    func showPopover() {
        guard let b = status.button else { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func handle(paths: [String]) {
        setStatus("smashing \(paths.count) item(s)…")
        DispatchQueue.global().async {
            let rs = Engine.process(paths: paths)
            DispatchQueue.main.async {
                self.results = (rs + self.results).prefix(6).map { $0 }
                self.refreshResults()
                let okAll = rs.allSatisfy { $0.ok } && !rs.isEmpty
                self.setStatus(okAll ? "done — \(rs.count) artifact(s)" : "finished with errors")
                if let b = self.status.button {
                    b.image = NSImage(systemSymbolName: okAll ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        b.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "smash")
                    }
                }
            }
        }
    }

    func setStatus(_ s: String) {
        statusLine.stringValue = s
        statusLine.toolTip = s
        statusLine.setAccessibilityLabel(s)
        statusLine.invalidateIntrinsicContentSize()
    }

    func refreshResults() {
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for r in results {
            let row = NSStackView()
            row.orientation = .horizontal
            let dot = NSTextField(labelWithString: r.ok ? "●" : "✕")
            dot.textColor = r.ok ? .systemGreen : .systemRed
            dot.font = .systemFont(ofSize: 10)
            let lbl = NSTextField(labelWithString: r.line)
            lbl.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            lbl.lineBreakMode = .byTruncatingMiddle
            lbl.toolTip = r.line
            row.addArrangedSubview(dot)
            row.addArrangedSubview(lbl)
            if let art = r.artifact {
                let btn = NSButton(title: "Reveal", target: self, action: #selector(reveal(_:)))
                btn.bezelStyle = .inline
                btn.font = .systemFont(ofSize: 10)
                btn.toolTip = art
                btn.identifier = NSUserInterfaceItemIdentifier(art)
                row.addArrangedSubview(btn)
            }
            resultsStack.addArrangedSubview(row)
        }
    }

    @objc func reveal(_ sender: NSButton) {
        if let p = sender.identifier?.rawValue {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
    }

    // ---------- settings UI ----------
    func makeSettingsVC() -> NSViewController {
        let vc = NSViewController()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        func label(_ s: String, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 11)
            if !bold { l.textColor = .secondaryLabelColor }
            return l
        }

        let title = NSTextField(labelWithString: "SMASH")
        title.font = .monospacedSystemFont(ofSize: 15, weight: .heavy)
        root.addArrangedSubview(title)

        let dropZone = PanelDropZone(frame: .zero)
        dropZone.onDrop = { [weak self] paths in self?.handle(paths: paths) }
        dropZone.onPick = { [weak self] in self?.pickInputs() }
        dropZone.widthAnchor.constraint(equalToConstant: 288).isActive = true
        dropZone.heightAnchor.constraint(equalToConstant: 64).isActive = true
        root.addArrangedSubview(dropZone)

        // mode + output
        root.addArrangedSubview(label("COMPRESSION", bold: true))
        modePop.addItems(withTitles: ["xz (lossless)", "gz (lossless)", "zstd (lossless)", "ai (semantic, offline)", "ai-api (semantic, LLM)"])
        let modes = ["xz", "gz", "zstd", "ai", "ai-api"]
        modePop.selectItem(at: modes.firstIndex(of: ud.string(forKey: "mode") ?? "xz") ?? 0)
        modePop.target = self; modePop.action = #selector(saveMode)
        root.addArrangedSubview(modePop)

        let outRow = NSStackView()
        outLabel.stringValue = ud.string(forKey: "outdir") ?? home("smashes")
        outLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        outLabel.lineBreakMode = .byTruncatingHead
        let outBtn = NSButton(title: "Output…", target: self, action: #selector(pickOut))
        outBtn.bezelStyle = .rounded; outBtn.controlSize = .small
        outRow.addArrangedSubview(outBtn)
        outRow.addArrangedSubview(outLabel)
        root.addArrangedSubview(outRow)

        // AI provider
        root.addArrangedSubview(label("AI / LLM (for ai-api mode)", bold: true))
        providerPop.addItems(withTitles: ["Local Ollama (no key)", "Anthropic API key", "Custom OpenAI-compatible URL"])
        let provs = ["ollama", "anthropic", "custom"]
        providerPop.selectItem(at: provs.firstIndex(of: ud.string(forKey: "provider") ?? "ollama") ?? 0)
        providerPop.target = self; providerPop.action = #selector(saveProvider)
        root.addArrangedSubview(providerPop)

        urlField.placeholderString = "endpoint URL (blank = provider default)"
        urlField.stringValue = ud.string(forKey: "aiURL") ?? ""
        urlField.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        urlField.target = self; urlField.action = #selector(saveURL)
        root.addArrangedSubview(urlField)

        modelField.placeholderString = "model (blank = provider default)"
        modelField.stringValue = ud.string(forKey: "aiModel") ?? ""
        modelField.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        modelField.target = self; modelField.action = #selector(saveModel)
        root.addArrangedSubview(modelField)

        keyField.placeholderString = "API key → stored in Keychain only"
        keyField.target = self; keyField.action = #selector(saveKey)
        root.addArrangedSubview(keyField)
        root.addArrangedSubview(label("Keys never touch disk — Keychain (this device only)."))

        // subscription / MCP network layer
        root.addArrangedSubview(label("SUBSCRIPTION AI — NO KEY", bold: true))
        root.addArrangedSubview(label("Your Claude subscription can drive smash directly\nthrough the MCP network layer instead of an API key."))
        let mcpBtn = NSButton(title: "Install AI Network Layer (MCP)", target: self, action: #selector(installMCP))
        mcpBtn.bezelStyle = .rounded
        root.addArrangedSubview(mcpBtn)

        // results
        root.addArrangedSubview(label("RECENT", bold: true))
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 4
        root.addArrangedSubview(resultsStack)

        statusLine.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLine.textColor = .secondaryLabelColor
        statusLine.lineBreakMode = .byWordWrapping
        statusLine.maximumNumberOfLines = 0
        statusLine.cell?.wraps = true
        statusLine.cell?.isScrollable = false
        statusLine.preferredMaxLayoutWidth = 288
        statusLine.widthAnchor.constraint(equalToConstant: 288).isActive = true
        statusLine.stringValue = "ready — \(smashPath())"
        statusLine.toolTip = statusLine.stringValue
        root.addArrangedSubview(statusLine)

        let quit = NSButton(title: "Quit smash", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .inline
        root.addArrangedSubview(quit)

        for v in [modePop, urlField, modelField, keyField] as [NSView] {
            v.widthAnchor.constraint(equalToConstant: 288).isActive = true
        }
        root.widthAnchor.constraint(equalToConstant: 320).isActive = true
        vc.view = root
        return vc
    }

    @objc func saveMode() {
        let modes = ["xz", "gz", "zstd", "ai", "ai-api"]
        ud.set(modes[modePop.indexOfSelectedItem], forKey: "mode")
    }
    @objc func saveProvider() {
        let provs = ["ollama", "anthropic", "custom"]
        ud.set(provs[providerPop.indexOfSelectedItem], forKey: "provider")
    }
    @objc func saveURL() { ud.set(urlField.stringValue, forKey: "aiURL") }
    @objc func saveModel() { ud.set(modelField.stringValue, forKey: "aiModel") }
    @objc func saveKey() {
        let provs = ["ollama", "anthropic", "custom"]
        let acct = provs[providerPop.indexOfSelectedItem]
        if keychainSet(acct == "ollama" ? "custom" : acct, keyField.stringValue) {
            setStatus("key saved to Keychain")
            keyField.stringValue = ""
        } else { setStatus("Keychain save failed") }
    }
    @objc func pickOut() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        if p.runModal() == .OK, let u = p.url {
            ud.set(u.path, forKey: "outdir")
            outLabel.stringValue = u.path
        }
    }
    func pickInputs() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowsMultipleSelection = true
        p.prompt = "Smash"
        if p.runModal() == .OK {
            handle(paths: p.urls.map { $0.path })
        }
    }
    @objc func installMCP() {
        setStatus("installing network layer…")
        DispatchQueue.global().async {
            var msg = ""
            if !FileManager.default.isExecutableFile(atPath: mcpPath()) {
                msg = "smash-mcp binary missing at ~/bin/smash-mcp — build it from the repo (mcp/smash-mcp) first."
            } else {
                // locate claude CLI
                let cands = [home(".local/bin/claude"), "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
                let claude = cands.first { FileManager.default.isExecutableFile(atPath: $0) }
                if let claude = claude {
                    func runClaude(_ args: [String]) -> (Int32, String) {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: claude)
                        p.arguments = args
                        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                        do { try p.run() } catch { return (127, "") }
                        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        p.waitUntilExit()
                        return (p.terminationStatus, out)
                    }
                    // `claude mcp add` exits 1 when the server is already
                    // registered, which is success from the user's chair —
                    // check registration first instead of reporting failure.
                    if runClaude(["mcp", "get", "smash"]).0 == 0 {
                        msg = "network layer already installed — Claude can call smash (no API key)."
                    } else {
                        let (rc, out) = runClaude(["mcp", "add", "-s", "user", "smash", mcpPath()])
                        if rc == 0 {
                            msg = "network layer registered — Claude can now call smash (no API key)."
                        } else if out.contains("already exists") {
                            msg = "network layer already installed — Claude can call smash (no API key)."
                        } else {
                            msg = "claude mcp add failed — run: claude mcp add -s user smash ~/bin/smash-mcp"
                        }
                    }
                } else {
                    msg = "claude CLI not found — run: claude mcp add -s user smash ~/bin/smash-mcp"
                }
            }
            DispatchQueue.main.async { self.setStatus(msg) }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
