import Foundation
import CryptoKit

public enum SmashDigest {
    /// Lowercase hex sha256, matching what smash writes into the manifest.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
