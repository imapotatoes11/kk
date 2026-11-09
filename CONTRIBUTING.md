# Contributing to kk

## Bugs and feature requests

Use [GitHub Issues](https://github.com/imapotatoes11/kk/issues). For bugs, include your kk version, macOS version, reproduction steps, expected behavior, and what actually happened. For capture issues, include the display arrangement and capture mode. For API issues, include the provider and model, with credentials and private content removed.

Discuss substantial features or interface changes in an issue before opening a large pull request.

## Development

Open `kk.xcodeproj` in Xcode and run the **kk** scheme. Development currently uses Xcode 27.2 and Swift 6; the app targets macOS 15 and later. Swift Package Manager resolves [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [MarkdownView](https://github.com/LiYanan2004/MarkdownView), and [Sparkle](https://github.com/sparkle-project/Sparkle).

The source is organized by responsibility under `Sources/kk`: app lifecycle, panel, chat, capture, annotations, API, storage, settings, and views. `Package.swift` supports package tooling and the tests in `Tests/kkTests`.

Run tests from the repository root:

```sh
swift test
```

UI tests need a logged-in macOS desktop session. Fixture-based tests do not replace manual verification of permissions, live providers, or physical multi-display capture. For relevant UI changes, check light and dark appearance and the full flow from opening kk to sending a question and a follow-up.

Keep pull requests focused. Explain the problem, resulting behavior, and validation performed. Call out anything you could not verify. Never include API keys, personal screenshots, or private conversation data.

## Documentation previews

The README uses actual kk views with staged screen content and deterministic local responses. See [the preview guide](docs/previews/README.md) to regenerate them. Keep sample content clearly labeled and use fictional data.

## Release packaging

Build a Release app with Xcode, or from the command line:

```sh
xcodebuild -project kk.xcodeproj -scheme kk -configuration Release \
  -derivedDataPath DerivedData -arch arm64 CODE_SIGN_IDENTITY=- build

Scripts/package-release.sh \
  DerivedData/Build/Products/Release/kk.app \
  DerivedData/releases/local
```

The packaging script verifies an arm64 executable, applies an ad-hoc signature, and creates an app ZIP, DMG, and SHA-256 checksums. It does not notarize or publish the app. Version metadata lives in `Sources/kk/Resources/Info.plist` and the Xcode project. Ad-hoc packaging uses `Scripts/adhoc.entitlements` to allow the bundled Sparkle framework to load under the hardened runtime. A future Developer ID distribution should sign all nested code with the same Team ID instead.

### Automatic updates

kk uses [Sparkle](https://sparkle-project.org/documentation/) for signed updates.
Settings → About shows the installed version, a manual check, and automatic check
and installation preferences. Automatic checks default to enabled; automatic
installation is opt-in. Checks use the public GitHub release feed and send no
conversation or screenshot content.

The updater's Ed25519 private key belongs in the release maintainer's login
Keychain under account `dev.kw2.kk`. The public key is embedded in
`Sources/kk/Resources/Info.plist` as `SUPublicEDKey`; normal builds need no extra
configuration. Keep a secure backup of the private key and never put it in this
repository. On another release machine, import the existing key using Sparkle's
`generate_keys --account dev.kw2.kk -f <private-key-file>` rather than generating
a replacement key.

After packaging, generate a signed appcast using Sparkle's tools (available in
`.build/artifacts/sparkle/Sparkle/bin` after `swift package resolve`):

```sh
Scripts/generate-appcast.sh \
  DerivedData/releases/local/kk.app \
  DerivedData/releases/local \
  .build/artifacts/sparkle/Sparkle/bin
```

Upload `appcast.xml` as an asset on every stable GitHub release alongside the ZIP,
DMG, and checksums. The app reads
`https://github.com/imapotatoes11/kk/releases/latest/download/appcast.xml`;
the generated archive URLs point to the specific `v<version>` tag. Increase
`CFBundleVersion` for every release. Build and packaging scripts do not publish
anything. A build without the public signing key cannot install updates.

Sparkle does not require public source code. The current feed and download URLs
use public GitHub release assets. If the source repository is private, host the
feed and archives separately at URLs users can access, then update `SUFeedURL`
and this script's download URL prefix.

When switching to Developer ID distribution, keep `dev.kw2.kk` and the existing
Sparkle key. Replace the packaging script's hardcoded ad-hoc signing with
inside-out Developer ID signing of the nested executables, framework, and app.
Omit the ad-hoc library-validation entitlement, use the hardened runtime and a
secure timestamp, then notarize and staple before creating the final update
archive and generating its Sparkle signature. Do not run the current ad-hoc
packaging script on a notarized app: it would replace the Developer ID signature.
