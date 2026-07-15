import AppKit
import Social
import UniformTypeIdentifiers

@objc(SmashShareViewController)
final class SmashShareViewController: SLComposeServiceViewController {
    private var stagedRoot: URL?

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("smash-share-\(UUID().uuidString)", isDirectory: true)
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { finish(error); return }
        stagedRoot = root

        let group = DispatchGroup()
        let lock = NSLock()
        var staged: [String] = []
        var firstError: Error?

        if let text = contentText, !text.isEmpty {
            let textURL = root.appendingPathComponent("Shared Text.txt")
            do {
                try text.write(to: textURL, atomically: true, encoding: .utf8)
                staged.append(textURL.path)
            } catch { firstError = error }
        }

        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                let type = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .fileURL) == true || UTType($0)?.conforms(to: .item) == true
                })
                guard let type = type else { continue }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    defer { group.leave() }
                    guard let source = url else {
                        lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
                        return
                    }
                    let target = self.uniqueTarget(for: source, in: root)
                    do {
                        try fm.copyItem(at: source, to: target)
                        lock.lock(); staged.append(target.path); lock.unlock()
                    } catch {
                        lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
                    }
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            group.wait()
            if staged.isEmpty {
                self.finish(firstError ?? NSError(domain: "SmashShare", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No supported shared files or text."]))
                return
            }
            self.runSmash(paths: staged, firstError: firstError)
        }
    }

    override func didSelectCancel() {
        cleanup()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func uniqueTarget(for source: URL, in root: URL) -> URL {
        var target = root.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = root.appendingPathComponent("\(n)-\(source.lastPathComponent)")
            n += 1
        }
        return target
    }

    private func runSmash(paths: [String], firstError: Error?) {
        guard let cli = Bundle.main.url(forResource: "smash", withExtension: nil) else {
            finish(NSError(domain: "SmashShare", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Bundled smash engine is missing."]))
            return
        }
        let out = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("smashes", isDirectory: true)
        do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        catch { finish(error); return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [cli.path, "-q", "-o", out.path + "/", "--"] + paths
        let errors = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errors
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.split(separator: "\n").last.map(String.init)
                    ?? "Smash failed."
                finish(NSError(domain: "SmashShare", code: Int(task.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]))
                return
            }
            finish(firstError)
        } catch { finish(error) }
    }

    private func finish(_ error: Error?) {
        DispatchQueue.main.async {
            self.cleanup()
            if let error = error {
                self.extensionContext?.cancelRequest(withError: error)
            } else {
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    private func cleanup() {
        if let root = stagedRoot { try? FileManager.default.removeItem(at: root) }
        stagedRoot = nil
    }
}

