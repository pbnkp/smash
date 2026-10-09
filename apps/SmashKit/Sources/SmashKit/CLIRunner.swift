#if os(macOS)
import Foundation

/// Bridge to the real `smash` CLI.
///
/// The desktop app deliberately shells out rather than reimplementing the
/// engine. smash's whole correctness story is that it builds candidate chains
/// and ships only the one that survives a byte-exact round-trip; a second,
/// parallel Swift implementation would be a second thing to keep correct and
/// would drift. One engine, one set of guarantees.
public struct SmashCLI: Sendable {

    public enum Failure: Error, CustomStringConvertible {
        case notInstalled
        case failed(status: Int32, stderr: String)

        public var description: String {
            switch self {
            case .notInstalled:
                return "smash v6 was not found. The Mac app uses ~/bin/smash (v6.1)."
            case .failed(let status, let stderr):
                let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return msg.isEmpty ? "smash exited with status \(status)." : msg
            }
        }
    }

    public var executable: URL

    /// Locate smash v6. A GUI app does not inherit a terminal PATH, so the
    /// usual install locations are probed. The newest v6 wins. Older smash
    /// is ignored: the windowed app is built for the v6 artifact format.
    public static func locate() -> SmashCLI? {
        let candidates = [
            "\(NSHomeDirectory())/bin/smash",
            "\(NSHomeDirectory())/.local/bin/smash",
            "/opt/homebrew/bin/smash",
            "/usr/local/bin/smash",
        ]
        var best: (cli: SmashCLI, parts: [Int])?
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let cli = SmashCLI(executable: URL(fileURLWithPath: path))
            guard let parts = v6Parts(cli.version()) else { continue }
            if best == nil || isNewer(parts, than: best!.parts) {
                best = (cli, parts)
            }
        }
        return best?.cli
    }

    /// "smash v6.1" -> [6, 1]. Anything that is not v6 is nil.
    static func v6Parts(_ version: String?) -> [Int]? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(separator: " ").last, token.hasPrefix("v6") else { return nil }
        let nums = token.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard nums.first == 6 else { return nil }
        return nums
    }

    private static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        let n = max(a.count, b.count)
        for i in 0..<n {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    public struct Result: Sendable {
        public var outputPaths: [URL]
        public var log: String
    }

    /// Run smash with the given arguments in `workingDirectory`.
    @discardableResult
    public func run(_ arguments: [String], in workingDirectory: URL) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        // Homebrew's bin must be on PATH so smash finds brotli/zstd/age/cjxl;
        // without it the engine silently loses candidate chains and produces
        // larger artifacts than the CLI would in a terminal.
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = env["PATH"].map { "\(extra):\($0)" } ?? extra
        process.environment = env

        let errPipe = Pipe(), outPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = outPipe

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stderr = String(decoding: errData, as: UTF8.self)
        let stdout = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure.failed(status: process.terminationStatus, stderr: stderr)
        }

        // smash announces each result as "encoded: <path>" / "decoded: <path>".
        var produced: [URL] = []
        for line in (stderr + "\n" + stdout).split(separator: "\n") {
            for prefix in ["encoded: ", "decoded: "] where line.hasPrefix(prefix) {
                let p = String(line.dropFirst(prefix.count))
                produced.append(URL(fileURLWithPath: p, relativeTo: workingDirectory).standardizedFileURL)
            }
        }
        return Result(outputPaths: produced, log: stderr + stdout)
    }

    public func version() -> String? {
        guard let r = try? run(["--version"], in: URL(fileURLWithPath: NSTemporaryDirectory())) else { return nil }
        return r.log.split(separator: "\n").first.map(String.init)
    }
}
#endif
