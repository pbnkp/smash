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
import QuartzCore
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

enum DropKind {
    case text, file, files, folder, artifact

    var prompt: String {
        switch self {
        case .text: return "I found text — drop it and I’ll grab it"
        case .file: return "I found a file — feed it to Smash"
        case .files: return "I found files — drop the whole stack"
        case .folder: return "I found a folder — drop it right here"
        case .artifact: return "Smash artifact found — drop to Restore"
        }
    }
}

func dropKind(_ pasteboard: NSPasteboard) -> DropKind? {
    let urls = pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    if !urls.isEmpty {
        if urls.contains(where: { $0.lastPathComponent.range(of: #"\.smash(?:\.\d+)?\.txt$"#, options: .regularExpression) != nil || $0.lastPathComponent.contains(".b64.") }) {
            return .artifact
        }
        if urls.count > 1 { return .files }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir), isDir.boolValue { return .folder }
        return .file
    }
    if let text = pasteboard.string(forType: .string), !text.isEmpty { return .text }
    return nil
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class Engine {
    static func run(args: [String], env extra: [String: String] = [:], input: Data? = nil,
                    timeout: TimeInterval = 300) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: smashPath())
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extra { env[k] = v }
        p.environment = env
        let so = Pipe(), se = Pipe(), si = Pipe()
        p.standardOutput = so; p.standardError = se
        if input != nil { p.standardInput = si }
        do { try p.run() } catch { return (127, "", "cannot launch smash: \(error.localizedDescription)") }
        if let input = input {
            DispatchQueue.global().async {
                si.fileHandleForWriting.write(input)
                try? si.fileHandleForWriting.close()
            }
        }
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

        let artifacts = paths.filter { $0.contains(".b64.") || $0.range(of: #"\.smash(?:\.\d+)?\.txt$"#, options: .regularExpression) != nil }
        let inputs = paths.filter { !artifacts.contains($0) }

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

    static func process(text: String) -> [JobResult] {
        let outdir = ud.string(forKey: "outdir") ?? home("smashes")
        try? FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
        var args: [String] = []
        var env: [String: String] = [:]
        switch ud.string(forKey: "mode") ?? "xz" {
        case "gz": args.append("-g")
        case "zstd": args.append("-z")
        case "ai": args.append("--ai")
        case "ai-api": args.append("--ai-api"); env = aiEnv()
        default: break
        }
        args += ["-o", (outdir as NSString).appendingPathComponent("Clipboard Text.txt"), "-"]
        let (rc, _, err) = run(args: args, env: env, input: Data(text.utf8))
        var results: [JobResult] = []
        for line in err.split(separator: "\n") {
            let s = String(line)
            if let r = s.range(of: "encoded: ") {
                let art = String(s[r.upperBound...])
                results.append(JobResult(ok: true, line: (art as NSString).lastPathComponent, artifact: art))
            }
        }
        if rc != 0 {
            results.append(JobResult(ok: false, line: "clipboard text failed: " + (err.split(separator: "\n").last.map(String.init) ?? ""), artifact: nil))
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
    var onTextDrop: ((String) -> Void)?
    var onDragKind: ((DropKind?) -> Void)?
    var onCatch: (() -> Void)?
    var onClick: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let kind = dropKind(sender.draggingPasteboard)
        layer?.backgroundColor = kind == nil ? NSColor.clear.cgColor : NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        onDragKind?(kind)
        return kind == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropKind(sender.draggingPasteboard) == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.backgroundColor = NSColor.clear.cgColor
        onDragKind?(nil)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { layer?.backgroundColor = NSColor.clear.cgColor; onDragKind?(nil) }
        onCatch?()
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty { onDrop?(urls.map { $0.path }); return true }
        if let text = sender.draggingPasteboard.string(forType: .string), !text.isEmpty {
            onTextDrop?(text); return true
        }
        return false
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Large, discoverable drop target inside the menu popover. It shares the same
// file-URL-only safety boundary as the status-item drop target and doubles as
// a button that opens a file/folder picker.
final class PanelDropZone: NSView {
    var onDrop: (([String]) -> Void)?
    var onTextDrop: ((String) -> Void)?
    var onPick: (() -> Void)?
    var onExpanded: ((Bool) -> Void)?
    private let label = NSTextField(labelWithString: "Drop files, folders, or text to Smash\nDrop Smash artifacts to Restore\nOr click to choose")
    private let idleText = "Drop files, folders, or text to Smash\nDrop Smash artifacts to Restore\nOr click to choose"

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drop files, folders, or text to Smash; drop Smash artifacts to Restore; or click to choose")
    }
    required init?(coder: NSCoder) { nil }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func react(to kind: DropKind?) {
        guard let kind = kind else {
            label.stringValue = idleText
            highlight(false)
            onExpanded?(false)
            return
        }
        label.stringValue = kind.prompt
        highlight(true)
        onExpanded?(true)
        playRandomGrabAnimation()
    }

    func catchDrop() {
        label.stringValue = "Got it — smashing…"
        guard !reducedMotion else { return }
        let chomp = CAKeyframeAnimation(keyPath: "transform.scale")
        chomp.values = [1.0, 0.91, 1.08, 1.0]
        chomp.keyTimes = [0, 0.35, 0.7, 1]
        chomp.duration = 0.32
        layer?.add(chomp, forKey: "smash-chomp")
    }

    private func playRandomGrabAnimation() {
        guard !reducedMotion else { return }
        layer?.removeAnimation(forKey: "smash-grab")
        let animation: CAKeyframeAnimation
        switch Int.random(in: 0..<3) {
        case 0:
            animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            animation.values = [0, -0.035, 0.035, -0.018, 0]
        case 1:
            animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [1.0, 1.055, 0.985, 1.025, 1.0]
        default:
            animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
            animation.values = [0, 5, -2, 3, 0]
        }
        animation.duration = 0.46
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(animation, forKey: "smash-grab")
    }

    private func highlight(_ active: Bool) {
        layer?.borderWidth = active ? 2 : 1
        layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.16)
                                          : NSColor.controlBackgroundColor.withAlphaComponent(0.45)).cgColor
        label.textColor = active ? .labelColor : .secondaryLabelColor
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let kind = dropKind(sender.draggingPasteboard)
        react(to: kind)
        return kind == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropKind(sender.draggingPasteboard) == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { react(to: nil) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.react(to: nil) } }
        catchDrop()
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty { onDrop?(urls.map { $0.path }); return true }
        if let text = sender.draggingPasteboard.string(forType: .string), !text.isEmpty {
            onTextDrop?(text); return true
        }
        return false
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
    weak var panelDropZone: PanelDropZone?
    var dropZoneHeight: NSLayoutConstraint?
    var remoteMCPField = NSTextField()
    var remoteMCPTokenField = NSSecureTextField()
    var mcpStateLabel = NSTextField(labelWithString: "Local: not checked\nEverywhere: HTTPS endpoint not configured")
    weak var settingsRoot: NSStackView?
    weak var settingsScroll: NSScrollView?

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = status.button {
            b.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "smash")
            b.action = #selector(togglePopover)
            b.target = self
            let dv = DropView(frame: b.bounds)
            dv.autoresizingMask = [.width, .height]
            dv.onDrop = { [weak self] paths in self?.handle(paths: paths) }
            dv.onTextDrop = { [weak self] text in self?.handle(text: text) }
            dv.onDragKind = { [weak self] kind in
                guard let self = self else { return }
                if kind != nil && !self.popover.isShown { self.showPopover() }
                self.panelDropZone?.react(to: kind)
            }
            dv.onCatch = { [weak self] in self?.panelDropZone?.catchDrop() }
            dv.onClick = { [weak self] in self?.togglePopover() }
            b.addSubview(dv)
        }
        popover.behavior = .transient
        popover.contentViewController = makeSettingsVC()
        DispatchQueue.global().async {
            let ok = self.verifyLocalMCP()
            DispatchQueue.main.async {
                self.mcpStateLabel.stringValue = ok
                    ? "Local: Smash MCP protocol ✓\nEverywhere: add and test an authenticated HTTPS URL"
                    : "Local: unavailable — click Connect / Repair This Mac\nEverywhere: HTTPS endpoint not configured"
            }
        }
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
                self.finish(results: rs)
            }
        }
    }

    func handle(text: String) {
        guard !text.isEmpty else { setStatus("clipboard has no text"); return }
        setStatus("smashing clipboard text…")
        DispatchQueue.global().async {
            let rs = Engine.process(text: text)
            DispatchQueue.main.async { self.finish(results: rs) }
        }
    }

    func finish(results rs: [JobResult]) {
        self.results = (rs + self.results).prefix(4).map { $0 }
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

    func setStatus(_ s: String) {
        statusLine.stringValue = s
        statusLine.toolTip = s
        statusLine.setAccessibilityLabel(s)
        statusLine.invalidateIntrinsicContentSize()
        resizeSettingsDocument()
    }

    func resizeSettingsDocument() {
        guard let root = settingsRoot, let scroll = settingsScroll else { return }
        root.layoutSubtreeIfNeeded()
        let height = max(1, root.fittingSize.height)
        root.setFrameSize(NSSize(width: 320, height: height))
        scroll.hasVerticalScroller = height > scroll.contentSize.height
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
        resizeSettingsDocument()
    }

    @objc func reveal(_ sender: NSButton) {
        if let p = sender.identifier?.rawValue {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
    }

    // ---------- settings UI ----------
    func makeSettingsVC() -> NSViewController {
        let vc = NSViewController()
        let root = FlippedStackView()
        settingsRoot = root
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
        panelDropZone = dropZone
        dropZone.onDrop = { [weak self] paths in self?.handle(paths: paths) }
        dropZone.onTextDrop = { [weak self] text in self?.handle(text: text) }
        dropZone.onPick = { [weak self] in self?.pickInputs() }
        dropZone.widthAnchor.constraint(equalToConstant: 288).isActive = true
        dropZoneHeight = dropZone.heightAnchor.constraint(equalToConstant: 76)
        dropZoneHeight?.isActive = true
        dropZone.onExpanded = { [weak self, weak root] expanded in
            guard let self = self else { return }
            self.dropZoneHeight?.constant = expanded ? 104 : 76
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                root?.animator().layoutSubtreeIfNeeded()
            }
            DispatchQueue.main.async { self.resizeSettingsDocument() }
        }
        root.addArrangedSubview(dropZone)

        let clipboardBtn = NSButton(title: "Smash Clipboard Text", target: self, action: #selector(smashClipboard))
        clipboardBtn.bezelStyle = .rounded
        clipboardBtn.widthAnchor.constraint(equalToConstant: 288).isActive = true
        root.addArrangedSubview(clipboardBtn)

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

        // MCP: local stdio and public HTTPS are distinct connection paths.
        root.addArrangedSubview(label("MCP CONNECTIONS", bold: true))
        root.addArrangedSubview(label("This Mac uses private stdio. Claude web/mobile needs\npublic HTTPS + OAuth; other clients may use bearer auth."))
        let mcpBtn = NSButton(title: "Connect / Repair This Mac", target: self, action: #selector(installMCP))
        mcpBtn.bezelStyle = .rounded
        root.addArrangedSubview(mcpBtn)

        remoteMCPField.placeholderString = "https://your-host.example/mcp"
        remoteMCPField.stringValue = ud.string(forKey: "remoteMCPURL") ?? ""
        remoteMCPField.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        remoteMCPField.target = self; remoteMCPField.action = #selector(saveRemoteMCP)
        root.addArrangedSubview(remoteMCPField)

        remoteMCPTokenField.placeholderString = "bearer token (non-OAuth clients) → Keychain"
        remoteMCPTokenField.target = self; remoteMCPTokenField.action = #selector(saveRemoteToken)
        root.addArrangedSubview(remoteMCPTokenField)

        let remoteRow = NSStackView()
        let testRemote = NSButton(title: "Test HTTPS", target: self, action: #selector(testRemoteMCP))
        let openConnectors = NSButton(title: "Claude Connectors…", target: self, action: #selector(openClaudeConnectors))
        testRemote.bezelStyle = .rounded; testRemote.controlSize = .small
        openConnectors.bezelStyle = .rounded; openConnectors.controlSize = .small
        remoteRow.addArrangedSubview(testRemote); remoteRow.addArrangedSubview(openConnectors)
        root.addArrangedSubview(remoteRow)

        mcpStateLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        mcpStateLabel.textColor = .secondaryLabelColor
        mcpStateLabel.maximumNumberOfLines = 0
        mcpStateLabel.preferredMaxLayoutWidth = 288
        mcpStateLabel.widthAnchor.constraint(equalToConstant: 288).isActive = true
        root.addArrangedSubview(mcpStateLabel)

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

        for v in [modePop, urlField, modelField, keyField, remoteMCPField, remoteMCPTokenField] as [NSView] {
            v.widthAnchor.constraint(equalToConstant: 288).isActive = true
        }
        root.widthAnchor.constraint(equalToConstant: 320).isActive = true
        root.layoutSubtreeIfNeeded()
        let contentHeight = max(1, root.fittingSize.height)
        root.frame = NSRect(x: 0, y: 0, width: 320, height: contentHeight)
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let viewportHeight = min(contentHeight, max(520, min(720, screenHeight - 120)))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 336, height: viewportHeight))
        settingsScroll = scroll
        scroll.documentView = root
        scroll.hasVerticalScroller = contentHeight > viewportHeight
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        vc.view = scroll
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
        p.prompt = "Smash or Restore"
        if p.runModal() == .OK {
            handle(paths: p.urls.map { $0.path })
        }
    }
    @objc func smashClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            setStatus("clipboard has no text")
            return
        }
        handle(text: text)
    }

    @objc func saveRemoteMCP() {
        ud.set(remoteMCPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "remoteMCPURL")
    }

    @objc func saveRemoteToken() {
        if keychainSet("mcp-remote", remoteMCPTokenField.stringValue) {
            remoteMCPTokenField.stringValue = ""
            setStatus("remote MCP token saved to Keychain")
        } else { setStatus("could not save remote MCP token") }
    }

    @objc func openClaudeConnectors() {
        let value = remoteMCPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            setStatus("HTTPS MCP URL copied — paste it into Claude Custom Connector")
        }
        if let url = URL(string: "https://claude.ai/settings/connectors") { NSWorkspace.shared.open(url) }
    }

    @objc func testRemoteMCP() {
        let value = remoteMCPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https" else {
            mcpStateLabel.stringValue = "Everywhere: enter a public https://…/mcp URL"
            setStatus("remote MCP requires HTTPS")
            return
        }
        saveRemoteMCP()
        mcpStateLabel.stringValue = "Everywhere: testing HTTPS…"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let token = keychainGet("mcp-remote")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Smash Menu","version":"5.2"}}}"#.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                if error == nil && (200...299).contains(code) && (body.contains("smash-mcp") || body.contains("serverInfo")) {
                    self.mcpStateLabel.stringValue = "Everywhere: HTTPS ✓ MCP initialize succeeded"
                    self.setStatus("remote HTTPS MCP is reachable")
                } else if code == 401 {
                    self.mcpStateLabel.stringValue = "Everywhere: HTTPS reached; authentication failed (401)"
                    self.setStatus("remote MCP needs the correct token or OAuth")
                } else {
                    self.mcpStateLabel.stringValue = "Everywhere: test failed (HTTP \(code))"
                    self.setStatus(error?.localizedDescription ?? "remote MCP did not initialize")
                }
            }
        }.resume()
    }

    private func verifyLocalMCP() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: mcpPath()) else { return false }
        let p = Process(), input = Pipe(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: mcpPath())
        p.standardInput = input; p.standardOutput = output; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let probe = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Smash Menu","version":"5.2"}}}
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

        """
        input.fileHandleForWriting.write(Data(probe.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return p.terminationStatus == 0 && text.contains("smash-mcp") && text.contains("smash_batch")
    }

    private func installClaudeDesktopConfig() -> Bool {
        let fm = FileManager.default
        let dir = home("Library/Application Support/Claude")
        let path = (dir as NSString).appendingPathComponent("claude_desktop_config.json")
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var object: [String: Any] = [:]
            if let data = fm.contents(atPath: path),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { object = parsed }
            var servers = object["mcpServers"] as? [String: Any] ?? [:]
            servers["smash"] = ["command": mcpPath(), "args": []] as [String: Any]
            object["mcpServers"] = servers
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch { return false }
    }

    @objc func installMCP() {
        setStatus("connecting local MCP…")
        mcpStateLabel.stringValue = "Local: testing canonical Smash MCP…"
        DispatchQueue.global().async {
            guard self.verifyLocalMCP() else {
                DispatchQueue.main.async {
                    self.mcpStateLabel.stringValue = "Local: failed — canonical smash-mcp did not answer"
                    self.setStatus("local MCP binary failed its initialize/tools test")
                }
                return
            }
            let desktopOK = self.installClaudeDesktopConfig()
            let cands = [home(".local/bin/claude"), home(".local/wrappers/claude"), "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            var codeOK = false
            if let claude = cands.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                func runClaude(_ args: [String]) -> (Int32, String) {
                    let p = Process(), pipe = Pipe()
                    p.executableURL = URL(fileURLWithPath: claude); p.arguments = args
                    p.standardOutput = pipe; p.standardError = pipe
                    do { try p.run() } catch { return (127, "") }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
                }
                let current = runClaude(["mcp", "get", "smash"])
                if current.0 == 0 && !current.1.contains(mcpPath()) { _ = runClaude(["mcp", "remove", "smash", "-s", "user"]) }
                if current.0 != 0 || !current.1.contains(mcpPath()) {
                    _ = runClaude(["mcp", "add", "-s", "user", "smash", "--", mcpPath()])
                }
                let verified = runClaude(["mcp", "get", "smash"])
                codeOK = verified.0 == 0 && verified.1.contains(mcpPath()) && verified.1.contains("Connected")
            }
            DispatchQueue.main.async {
                let code = codeOK ? "Claude Code ✓" : "Claude Code not found/connected"
                let desktop = desktopOK ? "Desktop config ✓ (restart Claude once)" : "Desktop config failed"
                self.mcpStateLabel.stringValue = "Local: Smash MCP ✓ — \(code); \(desktop)\nEverywhere: add and test an authenticated HTTPS URL"
                self.setStatus("local MCP repaired and protocol-tested")
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
