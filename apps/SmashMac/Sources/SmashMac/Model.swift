import Foundation
import SmashKit
import SwiftUI

/// One row in the app: a file the user dropped and what happened to it.
struct Job: Identifiable, Sendable {
    enum Outcome: Sendable {
        case pending
        case encoded(artifact: URL, originalBytes: Int, artifactBytes: Int, chain: String)
        case decoded(restored: URL)
        case failed(String)

        var resultURL: URL? {
            switch self {
            case .encoded(let artifact, _, _, _): return artifact
            case .decoded(let restored): return restored
            default: return nil
            }
        }
    }
    let id = UUID()
    var input: URL
    var outcome: Outcome = .pending

    var isArtifact: Bool { input.lastPathComponent.hasSuffix(".smash.txt") }
    var resultURL: URL? { outcome.resultURL }
}

struct EncodeChoices: Sendable {
    var portable: Bool
    var redact: Bool
    var encrypt: Bool
    var recordHost: Bool
    var smashFolder: Bool
    var reveal: Bool
    var origin: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var cliVersion: String?
    @Published var cliPath: String?
    @Published var cliMissing = false
    @Published var encrypt = false
    @Published var redact = false
    @Published var portableGzip = false
    /// Off unless the user asks. An artifact then does not carry this Mac's name.
    @Published var recordHost = false
    /// Off writes beside the input. On writes into ~/smashes.
    @Published var smashFolder = false
    @Published var revealWhenDone = true
    @Published var originLabel = ""

    private var cli: SmashCLI?

    init() {
        let d = UserDefaults.standard
        portableGzip = d.bool(forKey: Key.portable)
        redact = d.bool(forKey: Key.redact)
        encrypt = d.bool(forKey: Key.encrypt)
        recordHost = d.bool(forKey: Key.recordHost)
        smashFolder = d.bool(forKey: Key.smashFolder)
        originLabel = d.string(forKey: Key.origin) ?? ""
        if d.object(forKey: Key.reveal) == nil {
            revealWhenDone = true
        } else {
            revealWhenDone = d.bool(forKey: Key.reveal)
        }
        cli = SmashCLI.locate()
        cliMissing = (cli == nil)
        cliVersion = cli?.version()
        cliPath = cli?.executable.path
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(portableGzip, forKey: Key.portable)
        d.set(redact, forKey: Key.redact)
        d.set(encrypt, forKey: Key.encrypt)
        d.set(recordHost, forKey: Key.recordHost)
        d.set(smashFolder, forKey: Key.smashFolder)
        d.set(revealWhenDone, forKey: Key.reveal)
        d.set(originLabel, forKey: Key.origin)
    }

    func choices() -> EncodeChoices {
        EncodeChoices(
            portable: portableGzip,
            redact: redact,
            encrypt: encrypt,
            recordHost: recordHost,
            smashFolder: smashFolder,
            reveal: revealWhenDone,
            origin: originLabel
        )
    }

    func accept(urls: [URL]) {
        let settings = choices()
        let runner = cli
        for url in urls {
            let job = Job(input: url)
            let id = job.id
            jobs.append(job)
            Task.detached(priority: .userInitiated) {
                let outcome = AppModel.run(cli: runner, input: url, settings: settings)
                await MainActor.run { [weak self] in
                    guard let self, let index = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                    self.jobs[index].outcome = outcome
                    if settings.reveal, let result = outcome.resultURL {
                        NSWorkspace.shared.activateFileViewerSelecting([result])
                    }
                }
            }
        }
    }

    func clearFinished() {
        jobs.removeAll { job in
            if case .pending = job.outcome { return false }
            return true
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Smash"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.accept(urls: panel.urls)
            }
        }
    }

    nonisolated private static func run(cli: SmashCLI?, input: URL, settings: EncodeChoices) -> Job.Outcome {
        guard let cli else { return .failed(SmashCLI.Failure.notInstalled.description) }
        let artifact = input.lastPathComponent.hasSuffix(".smash.txt")
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("smashes", isDirectory: true)
        var args = ["-q"]
        var env = ["SMASH_PRINT_PATH": "1"]
        let work: URL
        if artifact {
            args.append("-d")
            args.append(input.path)
            work = input.deletingLastPathComponent()
        } else {
            if settings.portable { args.append("-g") }
            if settings.redact { args.append("--redact") }
            if settings.encrypt { args.append("--encrypt") }
            let origin = settings.origin
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if !origin.isEmpty {
                args.append("--origin")
                args.append(String(origin.prefix(120)))
            }
            if !settings.recordHost { env["SMASH_HOST"] = "-" }
            if settings.smashFolder {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                args.append("-o")
                args.append(folder.path)
                work = folder
            } else {
                work = input.deletingLastPathComponent()
            }
            args.append(input.path)
        }
        do {
            let result = try cli.run(args, in: work, environment: env)
            guard let out = result.outputPaths.first else {
                return .failed(artifact ? "smash reported no restored file." : "smash reported no artifact.")
            }
            if artifact {
                return .decoded(restored: out)
            }
            let head = (try? String(contentsOf: out, encoding: .utf8).prefix(2048)) ?? ""
            let manifest = SmashManifest.parse(String(head))
            let original = manifest.sourceBytes ?? fileSize(input)
            let packed = fileSize(out)
            return .encoded(
                artifact: out,
                originalBytes: original,
                artifactBytes: packed,
                chain: manifest.chain?.displayPath ?? "unknown"
            )
        } catch {
            return .failed(String(describing: error))
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }

    private enum Key {
        static let portable = "smash.mac.portable"
        static let redact = "smash.mac.redact"
        static let encrypt = "smash.mac.encrypt"
        static let recordHost = "smash.mac.recordHost"
        static let smashFolder = "smash.mac.smashFolder"
        static let reveal = "smash.mac.reveal"
        static let origin = "smash.mac.origin"
    }
}
