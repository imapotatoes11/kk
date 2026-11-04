# Contributing to kk

## Bugs and feature requests

Use [GitHub Issues](https://github.com/imapotatoes11/kk/issues). For bugs, include your kk version, macOS version, reproduction steps, expected behavior, and what actually happened. For capture issues, include the display arrangement and capture mode. For API issues, include the provider and model, with credentials and private content removed.

Discuss substantial features or interface changes in an issue before opening a large pull request.

## Development

Open `kk.xcodeproj` in Xcode and run the **kk** scheme. Development currently uses Xcode 27.2 and Swift 6; the app targets macOS 15 and later. Swift Package Manager resolves [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and [MarkdownView](https://github.com/LiYanan2004/MarkdownView).

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

The packaging script verifies an arm64 executable, applies an ad-hoc signature, and creates an app ZIP, DMG, and SHA-256 checksums. It does not notarize or publish the app. Version metadata lives in `Sources/kk/Resources/Info.plist` and the Xcode project.
