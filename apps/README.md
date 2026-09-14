# smash apps

Three targets, one engine.

| target | what it is | how it decodes |
|---|---|---|
| `SmashKit` | shared Swift package, macOS + iOS | manifest parser, chain model, base64/base85, native gzip |
| `SmashMac` | SwiftUI app with drag-drop and a menubar item | shells out to the real `smash` CLI |
| `SmashiOS` | SwiftUI artifact inspector | native, for the chains iOS can invert |

## Why the desktop app shells out

smash's correctness story is that it builds several candidate encodings and
ships only the one that survives a byte-exact round-trip. A second Swift
implementation of that engine would be a second thing to keep correct, and it
would drift. So the Mac app runs the CLI. One engine, one set of guarantees.

## Why the iOS app does not

iOS cannot spawn a subprocess, so there is no CLI to call. Apple's Compression
framework offers zlib, LZMA, LZ4 and LZFSE -- it does not offer brotli, zstd,
or the `.xz` container, which is what smash actually emits by default.

Rather than pretend, the iOS app does two honest things:

1. **Always** parses the manifest and shows full provenance: source, size,
   sha256, chain, tool version, encryption, and any reason the artifact will
   not restore byte-identically.
2. **Restores natively** when the chain is one iOS can genuinely invert. That
   is the gzip chain, produced by `smash -g`, and the app verifies the restored
   bytes against the sha256 in the manifest before claiming success.

For any other chain it names the missing capability ("this artifact uses
brotli") instead of failing opaquely, and tells you the fix: re-encode with
`smash -g`.

This is why `-g` and `-z` are now honoured as pins by the engine. Someone
asking for gzip usually needs that exact format for a reader that can only
invert that one thing; silently shipping a smaller brotli artifact would
defeat the reason they asked.

## Build

    swift test --package-path SmashKit          # 6 tests, real fixtures
    ./SmashMac/build-app.sh                     # -> SmashMac/build/Smash.app
    cd SmashiOS && xcodegen generate && \
      xcodebuild -scheme SmashiOS -sdk iphonesimulator build

Fixtures under `SmashKit/Tests/SmashKitTests/Fixtures` are real artifacts
produced by the CLI, not hand-written samples. If the artifact format changes,
the tests fail. That is intended.
