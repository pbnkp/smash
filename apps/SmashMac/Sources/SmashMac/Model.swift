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
    }
    let id = UUID()
    var input: URL
    var outcome: Outcome = .pending

    var isArtifact: Bool { input.lastPathComponent.hasSuffix(".smash.txt") }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var cliVersion: String?
    @Published var cliMissing = false
    /// Written next to the input by default, matching CLI behaviour.
    @Published var encrypt = false
    @Published var redact = false
    /// Forces `-g`, the one chain the iOS app can open unaided.
    @Published var portableGzip = false

    private var cli: SmashCLI?

    init() {
        cli = SmashCLI.locate()
        cliMissing = (cli == nil)
        cliVersion = cli?.version()
    }

    func accept(urls: [URL]) {
        for url in urls {
            var job = Job(input: url)
            jobs.append(job)
            let index = jobs.count - 1
            Task.detached(priority: .userInitiated) { [weak self] in
                let result = await self?.process(job)
                await MainActor.run {
                    guard let self, self.jobs.indices.contains(index) else { return }
                    job.outcome = result ?? .failed("Cancelled.")
                    self.jobs[index] = job
                }
            }
        }
    }

    private func process(_ job: Job) async -> Job.Outcome {
        guard let cli else { return .failed(SmashCLI.Failure.notInstalled.description) }
        let dir = job.input.deletingLastPathComponent()
        do {
            if job.isArtifact {
                let r = try cli.run(["-q", "-d", job.input.path], in: dir)
                guard let out = r.outputPaths.first else {
                    return .failed("smash reported no restored file.")
                }
                return .decoded(restored: out)
            } else {
                var args = ["-q"]
                if await portableGzip { args.append("-g") }
                if await redact { args.append("--redact") }
                if await encrypt { args.append("--encrypt") }
                args.append(job.input.path)
                let r = try cli.run(args, in: dir)
                guard let art = r.outputPaths.first else {
                    return .failed("smash reported no artifact.")
                }
                let head = (try? String(contentsOf: art, encoding: .utf8).prefix(2048)) ?? ""
                let manifest = SmashManifest.parse(String(head))
                let originalBytes = manifest.sourceBytes
                    ?? ((try? FileManager.default.attributesOfItem(atPath: job.input.path)[.size] as? Int) ?? 0)
                let artifactBytes = (try? FileManager.default
                    .attributesOfItem(atPath: art.path)[.size] as? Int) ?? 0
                return .encoded(
                    artifact: art,
                    originalBytes: originalBytes ?? 0,
                    artifactBytes: artifactBytes ?? 0,
                    chain: manifest.chain?.displayPath ?? "unknown"
                )
            }
        } catch {
            return .failed(String(describing: error))
        }
    }
}
