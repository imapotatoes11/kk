# kk

Native macOS screen-context Q&A.

Press ⌘⌥K (customizable in Settings), ask a question, and kk sends your prompt plus any attached screen image directly to an OpenAI-compatible model.

## Requirements

- macOS 15 or later
- Xcode current stable with Swift 6 support
- A vision-capable OpenAI-compatible Chat Completions endpoint

## Setup

Open `kk.xcodeproj` in Xcode and run the `kk` app target. The project resolves KeyboardShortcuts 3.x and MarkdownView 3.x through Swift Package Manager. `Package.swift` is also included for package-aware tooling and tests.

kk is a menu-bar utility and does not show a normal main window. Open Settings from the menu-bar item or the popup's gear button. Connection contains the endpoint, optional API key, and model; Shortcuts contains the global shortcut recorder and keyboard reference.

Drag the popup by its header and resize it from an edge or corner. Questions grow as text wraps, then scroll for longer prompts. Answers support Markdown (including code blocks and tables) and inline/display LaTeX using `$…$`, `$$…$$`, `\(…\)`, and `\[…\]`. Scroll up to pause automatic following; return to the bottom to resume. Each answer has a Copy action.

Customization includes opening size and position, snapping, popup material, always-on-top behavior, light/dark/system appearance, preset/system accents, answer text size, and optional model thinking. Full size opens a short 680-point-wide prompt; Compact opens a 480-point-wide launcher bar with kk, the editor, and settings. Permission/recovery notices add only the height they need. Both expand smoothly to 680 × 620 on the first question. Sizes are clamped to the display; manual resizing is preserved until reopening or changing opening size. Liquid Glass falls back to translucency before macOS 26. Reduce Motion skips size animations; Reduce Transparency uses an opaque background. Restore defaults leaves your connection and shortcut unchanged.

Choose Default position for the existing centered opening near the top of the display, or At cursor to open just below the pointer, clamped on-screen. This preference takes effect the next time the popup opens. Drag kk or the header toward the default position to snap the horizontal axis, vertical axis, or both. Dashed alignment guides appear while snapped and disappear on release. A small release margin prevents jitter; keep dragging to pull away. Turn off Snap to default position for free placement. Dragging across displays uses the default anchor on the display under the pointer.

Shortcuts offers optional ⌘C behavior inside the popup: standard text copy (default), copy the latest answer, or copy and close. Selected text retains normal copy behavior. Answer Copy buttons and the shortcut share a success/failure popup; closing happens only after a successful shortcut copy.

Enable Show model thinking to display reasoning or reasoning summaries shared by your provider, collapsed under a timed disclosure row. Models that do not expose thinking only show a waiting indicator. A subtle activity animation starts after 500 ms and respects Reduce Motion. Thinking remains in memory, separate from answer copying and follow-up request content.

## Permissions

When access is missing, the panel offers a Grant access button to request Screen Recording permission. You can also open Screen & System Audio Recording settings from the panel. kk retries capture when it becomes active after permission is granted; if macOS still requires a restart, quit and reopen kk.

## API configuration

Base URL defaults to `https://api.openai.com/v1`; the model defaults to `gpt-5.6-luna`. The API key is optional for local gateways and is stored only in Keychain when provided.

## Build

Build and run the app target from Xcode. The target uses the bundled `Resources/Info.plist` so `LSUIElement` and `NSScreenCaptureUsageDescription` are present.

## Privacy

Screenshots remain in memory only. Requests go directly to the configured API provider. kk has no analytics, conversation-history backend, or screenshot storage.
