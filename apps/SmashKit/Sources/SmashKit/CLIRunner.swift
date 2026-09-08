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
                return "The smash command-line tool was not found. Install it with: brew install pbnkp/smash/smash"
            case .failed(let status, let stderr):
                let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return msg.isEmpty ? "smash exited with status \(status)." : msg
            }
        }
    }

    public var executable: URL

    /// Locate the CLI. PATH is not inherited by a GUI app launched from
    /// Finder, so the usual install locations are probed explicitly.
    public static func locate() -> SmashCLI? {
        let candidates = [
            "\(NSHomeDirectory())/bin/smash",
            "\(NSHomeDirectory())/.local/bin/smash",
            "/opt/homebrew/bin/smash",
            "/usr/local/bin/smash",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return SmashCLI(executable: URL(fileURLWithPath: path))
        }
        return nil
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
