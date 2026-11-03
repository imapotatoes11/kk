# kk

Native macOS screen-context Q&A.

Press ⌘⌥K, ask a question, and kk sends your prompt plus any attached screen image directly to an OpenAI-compatible model.

## Requirements

- macOS 15 or later
- Xcode current stable with Swift 6 support
- A vision-capable OpenAI-compatible Chat Completions endpoint

## Setup

Open `kk.xcodeproj` in Xcode and run the `kk` app target. The project resolves KeyboardShortcuts 3.x and MarkdownView 3.x through Swift Package Manager. `Package.swift` is also included for package-aware tooling and tests.

kk is a menu-bar utility and does not show a normal main window. Use `kk Settings` from the menu-bar item to enter the endpoint, optional API key, and model.

## Permissions

When access is missing, the panel offers a Grant access button to request Screen Recording permission. You can also open Screen & System Audio Recording settings from the panel. kk retries capture when it becomes active after permission is granted; if macOS still requires a restart, quit and reopen kk. The fixed global shortcut is ⌘⌥K.

## API configuration

Base URL defaults to `https://api.openai.com/v1`; the model defaults to `gpt-5.6-luna`. The API key is optional for local gateways and is stored only in Keychain when provided.

## Build

Build and run the app target from Xcode. The target uses the bundled `Resources/Info.plist` so `LSUIElement` and `NSScreenCaptureUsageDescription` are present.

## Privacy

Screenshots remain in memory only. Requests go directly to the configured API provider. kk has no analytics, conversation-history backend, or screenshot storage.
