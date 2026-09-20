# kk — Native macOS Screen-Context Q&A
## Implementation specification for v0.1

This document is the implementation contract for **kk**, a small native macOS app for asking quick questions about whatever is currently on the user's screen.

The intended implementation model should **not redesign the product**. Product decisions, architecture, UX, scope, and defaults are defined here. Your job is to implement them cleanly and make pragmatic local choices only where this document leaves room.

> **Revision note (v3):** This revision incorporates the supplied UI Design Suite's macOS, accessibility, privacy, typography, focus, and motion guidance. It makes the screen preview, explicit send destination, focus and scroll rules, responsive panel layout, and accessible states concrete. The v2 architecture, API contract, and scope remain authoritative except where this document explicitly refines a UI interaction. Do not add a second design system or interpret web/landing-page advice as requirements for a small native panel.

---

# 1. Product definition

kk is a native macOS utility with one primary interaction:

> Press a global shortcut → kk captures the current display → type a question → receive a streamed AI answer in a small floating panel.

The model receives:
1. the user's textual question;
2. a screenshot captured immediately when kk is invoked;
3. prior messages in the current temporary session, if any.

The main use case is extremely fast visual Q&A:

- "what's wrong with this code?"
- "explain this error"
- "is this truth table right?"
- "summarize this paragraph"
- "what does this button do?"
- "what am I missing here?"
- "solve this step"
- "why is this layout broken?"

kk is **not** an agent, automation tool, command runner, editor integration, clipboard manager, filesystem assistant, or coding harness.

The defining product constraint is:

> kk does screen-aware inference only, with as little ceremony as possible.

---

# 2. Hard scope boundaries

## v0.1 MUST include

- Native macOS app
- Menu bar app
- Global keyboard shortcut
- Floating nonstandard panel
- Full-current-display screenshot capture
- OpenAI-compatible BYOK API configuration
- Streaming text responses
- Markdown rendering
- Syntax-highlighted code blocks
- Inline and block LaTeX rendering
- Temporary follow-up conversation within the current panel session
- Copy assistant response
- Screen Recording permission handling
- Settings window
- Secure API key storage in Keychain
- Light/dark appearance support through system colors
- An inspectable preview of the actual screenshot before it is sent

## v0.1 MUST NOT include

Do not implement any of the following:

- agents
- tools/function calling
- MCP
- shell execution
- CLI integration
- filesystem context
- Finder context
- selected text context
- clipboard history
- OCR pipeline
- local OCR
- screenshot annotation
- area selection
- window-only capture
- image attachments chosen by the user
- audio
- speech
- conversation sync
- cloud account/authentication
- kk-hosted backend
- analytics
- telemetry
- update framework
- browser extension
- iOS support
- model routing
- prompt templates
- personas
- multiple providers UI
- response editing
- inserting generated text into the previously active app
- persistent chat history
- persistent screenshots

If something is not required for the core flow, leave it out.

---

# 3. Technology choices

Use these choices unless they are technically impossible.

## Platform

- macOS 15+
- Swift 6 mode if practical
- Xcode current stable
- Native app only

## UI

- SwiftUI for ordinary views
- AppKit for the floating panel/window behavior
- SwiftUI content hosted inside a custom `NSPanel`

## Screen capture

Use **ScreenCaptureKit**.

Prefer:
- `SCShareableContent`
- `SCContentFilter`
- `SCScreenshotManager`

Do not use:
- shelling out to `screencapture`
- CGWindowList screenshots as the primary implementation
- Accessibility APIs for screenshots

## Global shortcut

Use:

`https://github.com/sindresorhus/KeyboardShortcuts`

Use **KeyboardShortcuts 3.0.1 or later within the 3.x line**, added through Swift Package Manager.

For v0.1, use a **fixed** global shortcut:

`⌘⌥K`

Use the package's hard-coded shortcut event API (`KeyboardShortcuts.events(for:)`) and react on **key-up**, not repeated key-down events.

Do **not** use `KeyboardShortcuts.Recorder` in v0.1. Current macOS 26/27 reports include recorder regressions, and Option+letter-only global shortcuts have also shown reliability problems with the macOS input method system. `⌘⌥K` avoids the Option-only-letter problem while keeping the mnemonic.

Shortcut customization is intentionally deferred to v0.2. Reliability is more important than configurability for the first build.

## Markdown / LaTeX

Use:

`https://github.com/LiYanan2004/MarkdownView`

Use **MarkdownView 3.0.0 or later within the 3.x line**.

Reasons:
- native SwiftUI rendering
- incremental streaming support
- code rendering
- text selection
- inline + block LaTeX
- macOS support

Use `StreamingMarkdownSource` / `StreamingMarkdownReader` while a response is streaming.

Enable math rendering with the package's LaTeX support.

Do not render Markdown using a `WKWebView`.

## Networking

Use native:
- `URLSession`
- `URLSession.bytes(for:)` or an equivalent async byte-stream approach
- `async/await`

Do not add an HTTP dependency.

## Persistence

- `UserDefaults` / `@AppStorage` for non-secret settings
- Keychain Services for API key
- no database
- no SwiftData required for v0.1

---

# 4. App lifecycle

kk is primarily a **menu bar utility**.

## App presentation

The app should not normally show a Dock icon.

Configure it as an accessory/menu-bar-style app with `LSUIElement = true`.

Prefer a SwiftUI `MenuBarExtra` plus a normal SwiftUI `Settings` scene. When opening Settings from an accessory app, explicitly activate the app if necessary so the Settings window reliably comes to the front.

The menu bar menu should contain:

- `Ask kk`
- separator
- `Settings…`
- separator
- `Quit kk`

`Ask kk` should invoke the exact same path as the global keyboard shortcut.

The menu bar item can use a simple monochrome icon. Do not spend meaningful implementation time on branding.

## Launch behavior

On launch:

1. initialize settings
2. initialize Keychain wrapper
3. register keyboard shortcut
4. create panel controller lazily or eagerly
5. show no main window
6. remain available from menu bar

Do not automatically show onboarding unless configuration is missing and the user invokes kk.

---

# 5. Core invocation sequence

This order matters because perceived latency is part of the product.

When the user presses `⌘⌥K` or chooses `Ask kk`:

1. If kk is already visible, dismiss it and cancel active work.
2. Determine the target display.
3. Create/reset a new in-memory session.
4. Show the kk panel **immediately** on that display.
5. Put keyboard focus into the prompt editor immediately.
6. In parallel, start capturing that display with ScreenCaptureKit.
7. Exclude kk's own application/windows from the capture filter so the floating panel is not included.
8. When capture finishes, update screen-context state to ready.

The user should be able to start typing while the screenshot is being acquired.

While capture is pending, show the screen chip as something equivalent to:

```text
▣ Screen · Capturing…
```

Disable Send until the screenshot is ready **unless** the user removes screen context or screen access is unavailable, in which case text-only sending can proceed immediately. An empty prompt and malformed API configuration still disable Send.

Preferred exclusion strategy:
- obtain `SCShareableContent`;
- find the `SCRunningApplication` whose process ID/bundle identifier matches kk;
- build `SCContentFilter(display:excludingApplications:exceptingWindows:)`.

Fallback:
- exclude kk's known `SCWindow` objects;
- if exclusion cannot be established reliably, perform capture before ordering the panel front rather than knowingly capturing kk itself.

The target interaction should feel like:

```text
⌘⌥K → panel appears → type immediately
```

not:

```text
⌘⌥K → mysterious pause → panel appears
```

---

# 6. Which display to capture

For v0.1, capture exactly one full display.

Choose the display containing the current mouse pointer at invocation time.

Implementation idea:

- read `NSEvent.mouseLocation`
- find the `NSScreen` whose frame contains that point
- map that screen to the corresponding `SCDisplay`

If mapping is imperfect, use display ID matching where possible.

Fallback:
- `NSScreen.main`
- then the first available `SCDisplay`

Do not capture all displays into one giant image.

---

# 7. Screenshot capture rules

Use ScreenCaptureKit and capture the chosen entire display.

Use:
- `SCShareableContent`
- `SCContentFilter`
- `SCStreamConfiguration`
- `SCScreenshotManager.captureImage(...)`

Explicitly exclude kk itself from the content filter as described above.

Set `showsCursor = true`. The pointer is useful visual context for questions such as "what does this do?" and also makes the display-under-mouse selection model coherent.

## Capture resolution

Do not capture a 5K/6K framebuffer at full resolution only to immediately throw pixels away.

Compute the display's pixel aspect ratio and configure capture near the final target size.

Target:
- maximum long edge: **2560 px**
- preserve aspect ratio
- never upscale a smaller display

If using `SCContentFilter.pointPixelScale`, use it to convert the filter's point-space content rect to native pixels before applying the 2560 px cap. Using `SCDisplay.width` / `height` as the native pixel basis is also acceptable.

## Image processing

Encode the final image as JPEG for maximum OpenAI-compatible provider support.

Target:
- JPEG quality: **0.85**
- color space: sRGB
- no metadata needed

If the resulting JPEG exceeds roughly **2.5 MB**:
1. reduce quality to ~0.75;
2. if still too large, reduce the long edge to ~2048 px and encode again.

Do not aggressively destroy text readability.

Store only:
- the processed `CGImage`/`NSImage` while needed;
- final JPEG `Data`;
- Base64 only while constructing the outgoing request.

Never write screenshots to disk in v0.1.

If the user removes screen context while capture is still running, cancel/ignore the capture result and release any image data as soon as practical.

---

# 8. Screen Recording permission

Screen capture requires macOS Screen Recording permission.

## Info.plist requirement

Add:

```text
NSScreenCaptureUsageDescription
```

Suggested value:

```text
kk uses Screen Recording access to include your current screen when answering questions.
```

## Permission flow

Do not request permission at app launch.

On invocation, check access with `CGPreflightScreenCaptureAccess()` before starting capture.

If access has not been granted, show kk's permission state:

```text
kk needs Screen Recording access to see your screen.

[Grant Access]
```

`Grant Access` should call `CGRequestScreenCaptureAccess()` as a direct result of the user's action.

If the request remains denied, show:

```text
[Open System Settings]
```

and deep-link to Privacy & Security → Screen & System Audio Recording / Screen Recording using the current supported System Settings URL if available.

After permission changes, retry capture when the app becomes active or when the user invokes kk again. Do not assume a relaunch is always required, but a small hint may say:

```text
If capture still fails after granting access, quit and reopen kk.
```

Do not crash.
Do not request repeatedly without user action.
Do not infer permission solely from one generic capture error; map known TCC/permission failures where possible.

---

# 9. Floating panel behavior

The floating panel is one of the most important parts of the app.

Use a custom AppKit `NSPanel`, with SwiftUI hosted using `NSHostingView`.

## Suggested panel configuration

Use the closest appropriate equivalent to:

```swift
NSPanel(
    contentRect: ...,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

Recommended behavior:

- `level = .floating`
- `isFloatingPanel = true`
- `hasShadow = true`
- transparent titlebar / no titlebar chrome
- `backgroundColor = .clear`
- panel content itself draws the background
- `collectionBehavior` includes:
  - `.canJoinAllSpaces`
  - `.fullScreenAuxiliary`
  - `.transient`
- panel should be able to become key for text input
- app should not behave like switching to a normal foreground app merely because kk is shown
- panel should stay above ordinary application windows
- not user-resizable in v0.1
- draggable by its background (`isMovableByWindowBackground = true`) if this behaves cleanly with the hosted SwiftUI hierarchy

A custom `NSPanel` subclass may override:

```swift
override var canBecomeKey: Bool { true }
override var canBecomeMain: Bool { false }
```

If `.nonactivatingPanel` conflicts with reliable keyboard focus, solve the focus behavior at the AppKit level. Preserve the visual/interaction semantics rather than blindly preserving one flag.

## Position

Target panel width:

**680 pt**

Actual width:

```text
min(680 pt, visibleDisplayWidth - 32 pt)
```

Position it horizontally centered on the captured display's visible frame.

Top edge:

approximately **88 pt below the top of the display's visible frame** (or lower if needed to avoid the menu bar/notch).

Do not place it dead-center vertically.

When the response grows, grow primarily downward.

Clamp the panel to the visible display area.

Keep the top edge visually anchored while changing height. On a short display, reduce the initial top offset as necessary to preserve space for content; never put the prompt, screen controls, or response behind the screen edge. If the panel is dragged, subsequent size changes respect its current top-left position and then clamp back into the visible frame. Do not snap it back to center after each token.

Maximum panel height:

`min(620 pt, visibleDisplayHeight - 120 pt)`

## Shape

- corner radius: ~12 pt
- 1 px-ish subtle border using system separator color / low-opacity stroke
- normal macOS shadow
- no glow
- no gradient
- no giant pill shape
- no glassmorphism-heavy translucent card

Use system adaptive background colors:
- something close to `NSColor.windowBackgroundColor`
- slightly elevated if needed

The panel should look compact, crisp, and native.

Use one opaque or nearly opaque panel surface. Respect macOS Reduce Transparency; do not use a translucent material behind small text or math. The border must remain visible in both appearances. The panel is a utility window, not a card containing more cards.

---

# 10. UI state model

Do **not** force capture state and response-generation state into one enum. They are independent.

Use two small state machines.

```swift
enum ScreenContextState {
    case capturing
    case ready(Data)       // processed JPEG
    case disabled
    case permissionRequired
    case failed(KKError)
}

enum GenerationState {
    case idle
    case streaming
    case completed
    case error(KKError)
}
```

This cleanly represents cases such as:
- prompt is editable while capture is still running;
- screen context was intentionally removed but generation is idle;
- capture failed but text-only Q&A is still available;
- generation failed while the screenshot remains ready for Retry.

## Idle

Visible:
- prompt editor
- compact screen-context indicator
- send button when permitted

## Streaming

Visible:
- submitted user prompt(s)
- streamed assistant answer
- stop/cancel button
- prompt editor disabled

## Completed

Visible:
- conversation
- copy button on assistant output
- follow-up prompt editor

## Error

Visible:
- short human-readable generation error
- Retry where meaningful
- prompt/conversation remains recoverable

## Screen permission required

The screen-context region becomes the permission UI. Do not erase an already typed prompt.

---

# 11. Visual structure

Build a compact, three-region panel with a stable reading order:

1. **Conversation region**, only after submission: user question as plain, selectable text (no chat bubble), followed by the assistant answer rendered as a small document. Subsequent turns use spacing and a hairline separator to distinguish them. One scroll view owns the conversation; no independently scrolling answer cards.
2. **Composer**, at the bottom: a plain-text editor with a one-line baseline, expanding to five lines. Place the send/stop control at its trailing edge. Use an SF Symbol with a visible hover tooltip and accessibility label; do not rely on the glyph alone. The editor remains visibly framed when focused. Keep this region available when the answer is long.
3. **Context row**, below the editor: a small `Screen` control with the capture state and remove action before the first send. It reads as a functional attachment, not a tag collection. The row may also show a short plain-text destination such as `Sends to api.example.com` before the first request, or expose that same sentence in the screenshot preview; the destination must be discoverable without opening Settings. Do not show the API path, key, or full URL in the panel.

At 680 pt wide, use about 14 pt outer inset, 12 pt between major regions, and 6–8 pt within a control. Align composer, conversation text, separator, and context row to the same leading edge. Keep the initial panel around 110–145 pt high. In the answered state, add only the height needed for content until the screen-clamped maximum. Do not pad a two-line answer into a giant empty box.

On a narrow display, keep at least 16 pt outside the panel. Wrap the destination below the context control or omit its inline label if the same information remains in the preview. The editor and its actions must never overlap; the conversation scrolls vertically. Honor right-to-left text direction for model output and prompts without mirroring the actual screenshot.

No dedicated `kk` header, avatar, timestamp, role badge, always-visible shortcut reminder, chat bubbles, or explanatory empty-state prose. The focused input is the first thing the user needs; the response gets visual priority after submission.

---

# 12. Prompt editor behavior

The prompt editor must support multiple lines.

Keyboard behavior:

- `Return` / `Enter`: send
- `Shift + Return`: insert newline
- While an input method is composing text, Return confirms the composition; it must not submit the prompt. Test this with a non-English IME.
- `Esc`: close the screenshot preview if open; otherwise dismiss the panel
- `⌘C`: standard copy behavior when text is selected
- Copy button copies the full assistant answer as plain Markdown source
- while streaming, the send button becomes Stop
- `Tab` moves through editor, context/preview, remove, and send/stop controls in a sensible order. Keyboard users can open and dismiss the preview without a mouse.

If SwiftUI's stock `TextField`/`TextEditor` cannot provide correct Return vs Shift+Return behavior cleanly, make a small `NSViewRepresentable` wrapper around `NSTextView`.

Prompt editor requirements:

- auto-focus on panel open
- placeholder:
  - first prompt with screen attached/capturing: `Ask about your screen…`
  - first prompt without screen access or after removal: `Ask a question…`
  - follow-up: `Ask a follow-up…`
- starts as one line
- grows up to roughly 5 lines
- after that, scroll internally
- no rich text
- plain text only
- The placeholder is a hint, not the only accessible label. Use `Question` for the editor's accessibility label and describe the Return/Shift-Return behavior in help text or tooltip rather than persistent extra chrome.

Do not send empty/whitespace-only prompts.

---

# 13. Screen context indicator

This control answers **what is attached, whether it is ready, and what will be sent**. It does not implicitly send anything. The provider receives a screenshot only when the user submits a prompt.

Before first submission, render these mutually exclusive states with text as well as an SF Symbol:

| State | Visible wording | Action |
| --- | --- | --- |
| Capture running | `Capturing screen…` | Send disabled; `Remove screen` cancels/ignores capture and enables text-only sending. |
| Ready | `Screen attached` | Clicking the label or preview icon opens the screenshot preview. Separate `Remove screen` action detaches it. |
| Removed | `No screen attached` | Text-only Send enabled. No recapture inside the session; close and reopen kk to capture again. |
| Permission missing | `Screen access needed` | Show `Grant access` / `Open System Settings`; text-only Send stays available. |
| Capture failed | `Screen unavailable` | Show a concise reason, offer text-only Send. |

The ready-state preview is **required**, not a stretch goal. Open a native popover or compact sheet anchored to `Screen attached`, max ~560 × 360 pt within the visible display; fit the processed image without cropping, keep its aspect ratio, and allow closing with Escape or by clicking the control again. Display the actual processed JPEG that will go to the provider, not a second capture or decorative mockup. Include `Current screen` and `Will send to <endpoint host> when you ask` in plain text, plus `Remove screen` as a clear action. Do not silently fetch or persist a preview file. If the capture is too large for the popover, scale for display only; sending still uses the same processed JPEG bytes. The preview is an inspectable disclosure, not an extra confirmation step.

Removing context **before first send** discards the image data for that session. After first send, replace the context row with a quiet `Screen sent` indicator: it can reopen the preview, but it has no remove control because removal cannot undo the already sent request. In this state the preview says `Sent to <endpoint host> with your first question`. Follow-ups retain the first message's image as specified in section 14. A future version may support changing that context; v0.1 does not.

If no image was attached to the first request, show `Text only` in follow-ups or omit the row if space is tight. Never say `Screen attached` when no screenshot will be sent.

---

# 14. Temporary session model

A session begins every time kk is opened from a hidden state through the global shortcut/menu item.

Closing/dismissing kk ends the session.

Do not persist the conversation.

Suggested data model:

```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
}

enum Role {
    case user
    case assistant
}
```

Session state should also include:

```swift
final class ChatSession {
    var messages: [ChatMessage]
    var screenContextState: ScreenContextState
    var generationState: GenerationState
    var currentCaptureTask: Task<Void, Never>?
    var currentGenerationTask: Task<Void, Never>?
}
```

The first user turn conceptually owns the screenshot context.

On follow-up requests, reconstruct the entire current session for the API:
- system prompt
- first user text + image
- first assistant answer
- subsequent user/assistant messages

Do not attach duplicate copies of the screenshot as separate new messages for every follow-up. It should remain part of the first user message in the serialized conversation.

---

# 15. OpenAI-compatible API design

kk is BYOK.

No kk backend exists.

The user configures:

- Base URL
- API key **(optional for providers that do not require one)**
- Model

Defaults:

```text
Base URL: https://api.openai.com/v1
Model: gpt-5.6-luna
```

The API key field is initially empty.

Do not hardcode or ship an API key.

An empty API key is valid configuration. This matters for localhost gateways such as LM Studio, Ollama-compatible bridges, LocalAI, or other OpenAI-compatible servers that may not require authentication.

## Endpoint

Use the traditional OpenAI-compatible endpoint:

```text
POST {baseURL}/chat/completions
```

Normalize the base URL:
- trim whitespace
- remove trailing `/`
- if user enters a URL already ending in `/chat/completions`, avoid duplicating the path

The compatibility goal matters more than targeting every OpenAI-specific feature.

## Headers

Always send:

```http
Content-Type: application/json
Accept: text/event-stream
```

If, and only if, the API key is non-empty, also send:

```http
Authorization: Bearer <api-key>
```

Do not send an empty `Authorization: Bearer` header.

No arbitrary custom headers in v0.1.

## Request body

Keep the request intentionally minimal for provider compatibility:

```json
{
  "model": "gpt-5.6-luna",
  "messages": [...],
  "stream": true
}
```

Do **not** send speculative provider-specific fields by default.

Do not send:
- tools
- tool_choice
- reasoning config
- temperature
- top_p
- seed
- response_format
- metadata
- store

unless a compatibility fix later proves one necessary.

## System prompt

Use this default exactly or very close to it:

```text
You are kk, a concise assistant answering questions using the user's screen as visual context. Answer the user's question directly. Pay close attention to visible text, UI, code, diagrams, math, and errors. Use Markdown when useful. For math, use `$...$` for inline math and `$$...$$` for display math. Do not describe the screenshot unless it helps answer the question.
```

Do not expose system-prompt editing in v0.1.

---

# 16. Multimodal message format

Use the widely supported Chat Completions multimodal structure.

The first user message should serialize approximately as:

```json
{
  "role": "user",
  "content": [
    {
      "type": "text",
      "text": "why is this wrong?"
    },
    {
      "type": "image_url",
      "image_url": {
        "url": "data:image/jpeg;base64,<BASE64>"
      }
    }
  ]
}
```

If screenshot context was removed:

```json
{
  "role": "user",
  "content": "why is this wrong?"
}
```

Assistant messages:

```json
{
  "role": "assistant",
  "content": "..."
}
```

Follow-up user messages can use simple string content unless future image support exists.

---

# 17. Streaming

Responses must stream.

Parse OpenAI-style SSE.

Typical event:

```text
data: {"choices":[{"delta":{"content":"hello"}}]}
```

Termination:

```text
data: [DONE]
```

Implementation rules:

1. validate the HTTP status before treating the body as a successful stream;
2. parse SSE events, using blank lines as event boundaries;
3. collect one or more `data:` lines belonging to the same event;
4. ignore comment/keepalive lines beginning with `:`;
5. if the event payload is `[DONE]`, finish normally;
6. otherwise decode JSON;
7. read `choices[0].delta.content` when present;
8. append content to the current assistant message;
9. update the Markdown streaming source;
10. keep UI mutations on the main actor.

Also detect a streamed JSON `error` object and surface it as an API error instead of silently waiting for `[DONE]`.

Provider quirks should fail gracefully.

If a provider returns a normal non-streaming JSON body despite `stream: true`, optionally support extracting:
`choices[0].message.content`.

That fallback is useful but secondary.

---

# 18. Cancellation

While streaming:

- Send button becomes a Stop button.
- Clicking Stop cancels the active request task.
- `Esc` hides the panel and cancels the request.
- Invoking kk while the panel is already visible should dismiss it and cancel active work.

Do not allow multiple simultaneous completion requests in one panel.

Cancellation is not an error state.

If a partial answer exists when Stop is pressed, keep the partial answer visible and treat the session as completed enough to allow a follow-up.

---

# 19. Response rendering

Use `MarkdownView` 3.x.

While streaming:
- use its incremental/streaming API
- append incoming text to one streaming source
- avoid reparsing a giant string from scratch on every token if the library offers a better path

Enable:
- headings
- paragraphs
- lists
- emphasis
- links
- blockquotes
- inline code
- fenced code
- tables where supported
- inline math `$...$`
- display math `$$...$$`

Styling should be restrained:
- system body font
- headings not enormous
- monospaced code
- subtle code block background
- text selection enabled
- links use system accent color
- horizontal scrolling for code/math where necessary

Do not invent custom Markdown syntax.

## Remote images in model output

Do **not** let Markdown output silently fetch remote images.

Configure/override MarkdownView's image rendering so that `http://` and `https://` image references are rendered as a small link/placeholder instead of automatically downloading the image. This avoids unexpected network requests triggered solely by model-generated Markdown.

Normal Markdown links remain clickable and open in the user's default browser.

---

# 20. Scrolling behavior

Assistant output goes inside a vertical scroll view once needed.

During streaming:
- follow the newest output only while the conversation is at or near the bottom (about 40 pt threshold).
- if the user scrolls upward or selects text, stop following. Do not fight the scroll position on every token.
- when the user returns to the bottom, resume following. No floating "jump to latest" button is necessary in v0.1.

When a new question is submitted, bring that turn into view once. On opening the panel, the conversation is empty and the editor is visible. The composer/context region remains outside the scrolling conversation so follow-up input does not vanish beneath long output.

Code blocks should support horizontal scrolling without forcing the entire panel wider.

---

# 21. Panel sizing

The panel should animate between sizes rather than abruptly jump.

Approximate size targets:

## Initial

- width: 680
- height: ~104–140 depending on editor growth

## With response

- width: 680
- minimum height: ~220
- maximum height: ~620 or screen clamp

The assistant response area should consume the flexible height.

Do not make every response expand the panel to maximum height immediately.

Use a short native-feeling animation:
- roughly 0.18–0.25 s
- ease-out or spring
- no bouncy spectacle

Animate region reveal and deliberate size transitions, not every streamed token. If a response would keep growing, settle at the screen-clamped maximum and let the conversation scroll. Honor Reduce Motion by removing the panel movement/size animation while keeping state changes immediate and readable.

---

# 22. Dismissal rules

Hide the panel when (unless a screenshot preview is open, in which case Escape closes that preview first):

- user presses `Esc`
- user presses the global shortcut while it is already visible

Do **not** automatically dismiss merely because another app becomes active or the user clicks outside, at least for v0.1. Accidental disappearance while reading an answer is annoying.

If click-outside dismissal is trivial and reliable, it may be added later, but it is not required.

When hidden:
- cancel active generation
- cancel/ignore active screen capture
- clear temporary messages
- release screenshot data
- clear prompt
- reset streaming and screen-context state

Next invocation is a brand-new session and captures a new screenshot.

---

# 23. Settings window

Use a normal native Settings scene/window.

Sections:

## API

Fields:

```text
Base URL
API Key (optional)
Model
```

Defaults:

```text
Base URL: https://api.openai.com/v1
Model: gpt-5.6-luna
```

API key:
- secure field
- stored in Keychain
- never stored in `UserDefaults`
- never printed to logs

A small descriptive label:

```text
kk sends your question and any attached screen image directly to this OpenAI-compatible endpoint.
```

Use a single, ordinary native Settings window titled `kk Settings`, with three vertically aligned labeled fields. Show the effective destination host in the explanatory sentence when the URL is valid. `API key (optional)` is a secure entry field and must remain visually distinguishable from a saved-but-masked value; clearing it must actually remove the Keychain value. Keep spacing around 12–16 pt, use system form controls and native focus rings, and place validation text immediately under the affected field. Do not invent a multi-pane Settings navigation for three fields. Make the menu bar Settings action reliable; support `⌘,` when the app has keyboard focus and the normal Settings command can be installed without an app-wide shortcut hook.

No General section is needed in v0.1.

Do not implement Launch at Login yet.
Do not add a theme selector. Follow system appearance.

---

# 24. Missing configuration behavior

An API key is **not required** globally because some OpenAI-compatible providers accept unauthenticated localhost requests.

If Base URL or model is invalid/empty, show a direct configuration error:

```text
Finish API setup before sending.

[Open Settings]
```

If the default OpenAI endpoint is used with no key, allow the request to be attempted; OpenAI will return 401 and kk should surface the normal credentials error.

Do not automatically open Settings every launch.

---

# 25. Keychain

Create a tiny Keychain service.

Example API:

```swift
protocol APIKeyStoring {
    func loadAPIKey() -> String?
    func saveAPIKey(_ value: String) throws
    func deleteAPIKey() throws
}
```

Use:
- generic password item
- service name based on kk's bundle identifier
- account name such as `openai-compatible-api-key`

Avoid third-party Keychain packages unless native APIs become disproportionately messy.

Never log the key.

If the user clears the API key field, delete the Keychain item rather than storing an empty secret. The networking layer should then simply omit the Authorization header.

---

# 26. Error model

Create a small typed error model.

Suggested cases:

```swift
enum KKError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case screenCapturePermission
    case screenCaptureFailed(String)
    case network(String)
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case invalidResponse
    case streamFailed(String)
}
```

User-facing copy should be short.

Examples:

### 401 / 403

```text
The API rejected your credentials.
Check your API key in Settings.
```

### 429

```text
The API rate limit was reached.
Try again in a moment.
```

### 5xx

```text
The provider returned an error.
```

### network offline

```text
Couldn't reach the API.
Check your connection and Base URL.
```

### unsupported vision model

If the provider reports an image/vision-related error:

```text
This model may not support image input.
Try a vision-capable model in Settings.
```

Show the server's concise message underneath only if it is useful and not huge.

Never dump raw JSON into the panel.

---

# 27. Logging

Keep logging minimal.

In Debug builds, useful logs may include:
- panel invocation
- selected display dimensions
- screenshot byte size
- request endpoint host/path
- HTTP status
- stream start/end
- error category

Never log:
- API key
- Authorization header
- screenshot Base64
- screenshot pixels
- full prompts
- full model responses

Use `Logger` / OSLog if desired.

---

# 28. Privacy behavior

Privacy is simple and should be reflected in implementation:

- screenshots remain in memory only;
- no kk server;
- screenshot and prompt go directly to the configured provider;
- no analytics;
- no stored conversation history;
- no stored screenshots.

The Settings view may include one sentence explaining this.

Do not build a privacy-policy UI in v0.1.

---

# 29. Suggested code organization

Use something close to:

```text
kk/
├── App/
│   ├── KKApp.swift
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   └── MenuBarContent.swift
│
├── Panel/
│   ├── KKPanel.swift
│   ├── PanelController.swift
│   └── PanelPositioning.swift
│
├── Chat/
│   ├── ChatSession.swift
│   ├── ChatMessage.swift
│   ├── ScreenContextState.swift
│   ├── GenerationState.swift
│   └── ChatController.swift
│
├── Views/
│   ├── PanelRootView.swift
│   ├── PromptEditor.swift
│   ├── PromptHeaderView.swift
│   ├── ResponseView.swift
│   ├── ScreenContextView.swift
│   ├── ErrorView.swift
│   └── PermissionView.swift
│
├── Capture/
│   ├── ScreenCaptureService.swift
│   ├── DisplayResolver.swift
│   └── ImageProcessor.swift
│
├── API/
│   ├── OpenAICompatibleClient.swift
│   ├── APIModels.swift
│   ├── SSEParser.swift
│   └── APIConfiguration.swift
│
├── Storage/
│   ├── KeychainStore.swift
│   └── Preferences.swift
│
├── Settings/
│   └── SettingsView.swift
│
├── Shared/
│   ├── KKError.swift
│   └── Constants.swift
│
└── Resources/
```

Exact filenames can vary, but keep responsibilities separated.

Do not put the entire app into one giant `ContentView.swift`.

---

# 30. Main types and responsibilities

## `AppState`

Global application state.

Owns:
- panel controller
- capture service
- preferences
- API key store

Handles:
- global shortcut callback
- menu bar Ask action
- opening Settings

## `PanelController`

Owns the `NSPanel`.

Responsibilities:
- create panel
- mount SwiftUI root view
- show/hide
- position on display
- focus prompt
- animate size changes
- expose `isVisible`

## `ChatController`

Prefer `@MainActor` + `@Observable` where convenient.

Owns:
- active session
- prompt
- current assistant output
- screen-context state
- generation state
- capture/generation tasks

Responsibilities:
- submit
- stop
- follow-up
- reset
- transform session into API messages
- consume streaming output

## `ScreenCaptureService`

Responsibilities:
- find/capture chosen display
- return processed JPEG
- surface permission failures

## `OpenAICompatibleClient`

Responsibilities:
- construct request
- issue URLSession request
- validate HTTP status
- parse SSE
- expose token/chunk stream

It should know nothing about SwiftUI.

## `KeychainStore`

Only secret storage.

## `Preferences`

Wrap persisted settings:
- base URL
- model
- anything else non-secret

---

# 31. Concurrency model

Prefer structured concurrency.

Network API concept:

```swift
struct OpenAICompatibleClient {
    func streamCompletion(
        request: ChatCompletionRequest,
        configuration: APIConfiguration
    ) -> AsyncThrowingStream<String, Error>
}
```

or an equivalent `async` method that accepts an `onDelta` closure.

Keep networking off the main actor.

Keep UI mutations on `@MainActor`.

Cancellation of the outer `Task` must propagate to URLSession streaming.

Avoid detached tasks unless required.

---

# 32. API model structs

Create explicit `Codable` request/response types rather than raw `[String: Any]`.

Possible conceptual model:

```swift
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool
}
```

Multimodal content can use an enum with custom Codable:

```swift
enum MessageContent: Encodable {
    case text(String)
    case parts([ContentPart])
}
```

Parts:

```swift
enum ContentPart {
    case text(String)
    case imageURL(String)
}
```

Do not over-generalize for tools/audio/functions.

Response decoding only needs fields actually used:

```swift
struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
```

Also define a small error-response type for:

```json
{
  "error": {
    "message": "..."
  }
}
```

---

# 33. Exact first-request serialization

For a new session with screenshot:

```text
messages[0] = system
messages[1] = user(text + image)
```

Example:

```json
[
  {
    "role": "system",
    "content": "You are kk..."
  },
  {
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "why is this wrong?"
      },
      {
        "type": "image_url",
        "image_url": {
          "url": "data:image/jpeg;base64,..."
        }
      }
    ]
  }
]
```

Follow-up after one completed answer:

```json
[
  { "role": "system", ... },
  { "role": "user", "content": [text, image] },
  { "role": "assistant", "content": "..." },
  { "role": "user", "content": "okay but why?" }
]
```

Do not make the user restate the visual context.

---

# 34. UI style rules

Use the following style consistently.

## Overall

- mostly monochrome
- compact
- high information density without feeling cramped
- SF system text for UI and prose; system monospaced font for code; no downloaded or marketing-style display font in a utility panel
- strong spacing/alignment
- use the system accent sparingly for focus, links, and an available Send action; do not invent a second brand hue
- thin separators/borders
- moderate corner radius
- no decorative artwork

Typography: use the system body style around 13–14 pt for the composer and answer, 12–13 pt for secondary context and controls, and restrained semibold text for Markdown headings. Keep normal sentence case. Use a comfortable line height (~1.35–1.5 for prose), and avoid shrinking the answer just to fit more lines. Code stays monospaced and horizontally scrollable. If text is enlarged by accessibility features or custom system scaling, let rows grow and scroll; do not clip controls or the last line of an answer. The desktop system font is intentional here: the skill's display-font guidance is for larger branded surfaces, not a native transient utility.

Use adaptive macOS semantic colors (`labelColor`, `secondaryLabelColor`, `windowBackgroundColor`, `separatorColor`, link/accent) and verify contrast in light and dark appearances, including disabled and error states. Body text should meet about 4.5:1 and meaningful controls/icons about 3:1. Do not communicate `capturing`, `failed`, or `sent` by color alone. Use SF Symbols from one consistent weight and render icon-only controls with a tooltip and spoken label. A tiny `×` glyph is not an acceptable effective hit target; target at least ~24 × 24 pt for desktop controls.

## Avoid

Do not use:
- gradients
- glowing borders
- huge title text
- glass cards everywhere
- bright colored backgrounds
- vertical colored accent bars
- tiny uppercase gray category labels
- excessive pills
- excessive nested cards
- chat bubbles
- emoji branding
- oversized buttons

The app should feel more like a polished macOS utility than a generic AI chat client.

---

# 35. Motion

Motion should be subtle and functional.

Animate:
- panel appearing (opacity and at most a few points of movement)
- deliberate panel height changes (top edge stays fixed)
- response region appearing
- send → stop icon transition without moving neighboring controls

Recommended durations:
- hover/press: ~0.10–0.15 s
- panel/region reveal: ~0.18–0.24 s; hide can be faster

Avoid:
- perpetual animation
- gradient animation
- large scale/zoom
- excessive spring bounce
- typing fake-cursor gimmicks

The streamed text itself provides enough motion.

Respect `accessibilityReduceMotion` for all spatial movement and size interpolation. Keep a simple appearance change, or no animation, under Reduce Motion. No per-token panel animation and no spinner if the `Capturing screen…` or `Thinking…` text already conveys progress; a standard indeterminate indicator is fine only if capture/generation remains pending perceptibly. UI actions must remain usable during an animation.

---

# 36. Accessibility

Accessibility is part of the v0.1 interaction, not an optional polish pass.

Ensure:
- controls have meaningful accessibility labels
- keyboard navigation reaches editor, preview, remove, Send/Stop, Copy, Retry, and permission actions in reading order
- native focus indicator is visible in both appearances; the preview does not trap focus and returns it to `Screen attached` when dismissed
- Settings fields have labels
- screen context remove button is labeled
- copy button is labeled
- stop button is labeled
- status changes expose concise text (`Capturing screen`, `Screen attached`, `Answer streaming`, `Answer complete`, or the specific error) to VoiceOver; do not announce every streamed token
- the screenshot preview has a descriptive label (`Captured current screen`) and a text description of the send destination; do not claim an AI-generated description of its pixel contents
- text and controls remain legible under Increase Contrast, Reduce Transparency, and larger text; test both light and dark system appearance
- focus does not jump when capture completes or as streaming tokens arrive

Use native accessibility APIs and system controls rather than a custom accessibility framework.

---

# 37. Keyboard/focus edge cases

Pay particular attention to these:

## On initial invocation

Prompt editor must receive focus immediately.

The user should be able to:

```text
⌘⌥K
type question
Return
```

without clicking anything.

## After response completes

Follow-up editor should be focusable immediately.

If focus was in the composer or on Stop, restore it to the follow-up editor. If the user is selecting or reading response text, leave focus and scroll position alone. Capture completion must never steal focus from typing.

## Escape

If the screenshot preview is open, Escape closes that preview first and returns focus to its trigger. Otherwise Escape dismisses kk. If a standard Settings window is key, Escape follows its native behavior rather than hiding an unrelated kk panel.

If an `NSTextView` is being used, ensure it does not swallow Escape.

## Repeated shortcut

If kk is visible:
- `⌘⌥K` hides it.

If kk is hidden:
- `⌘⌥K` performs a fresh capture and opens a new session.

---

# 38. Copy behavior

Assistant answers should be selectable.

Include one small `Copy` button for the current/last assistant answer.

Copy the assistant's raw Markdown string to the pasteboard.

After copying:
- briefly change label/icon to indicate success;
- return to normal after ~1 second.

Do not implement:
- copy as HTML
- copy rendered rich text
- export
- save to file

---

# 39. Links

Markdown links should be clickable.

Open external links with the default browser using the normal macOS mechanism.

Do not navigate inside kk.

No embedded browser.

---

# 40. Settings validation

Base URL:
- must parse as HTTP or HTTPS URL
- HTTPS is expected for remote providers
- allow HTTP because localhost/local gateways are legitimate

API key:
- optional
- when present, allow arbitrary text after trimming accidental surrounding whitespace
- do not enforce OpenAI `sk-` format

Model:
- arbitrary non-empty string
- do not fetch/force a model list
- do not assume OpenAI model naming

This is important for OpenAI-compatible providers.

---

# 41. Local providers

The BYOK design should naturally allow local gateways.

Examples:

```text
http://localhost:11434/v1
http://127.0.0.1:1234/v1
```

Do not add special Ollama/LM Studio code.

If their OpenAI-compatible endpoint supports the specified Chat Completions shape and image input, it should work automatically.

If a local provider does not support vision, the user gets the normal model/provider error.

---

# 42. Security constraints

- API key only in Keychain
- no credentials in logs
- no screenshot on disk
- no arbitrary code execution
- no untrusted HTML rendering
- no shell
- no browser scripting
- no Accessibility permission
- no Input Monitoring permission should be needed for the fixed `KeyboardShortcuts` global hotkey
- only Screen Recording permission is expected for core functionality
- include `NSScreenCaptureUsageDescription`

Prefer App Sandbox if it does not fight ScreenCaptureKit / networking / shortcut behavior.

Required outbound network client entitlement if sandboxed.

Do not add broad entitlements without need.

---

# 43. First-run behavior

Do not build a multi-page onboarding flow.

On first launch:
- app quietly appears in menu bar.

On first invocation:
- show/focus the panel immediately;
- if Screen Recording permission is absent, show permission UI for the screen-context region;
- otherwise begin screen capture;
- show `Ask about your screen…` only when a capture can be attached; with denied/removed context, use `Ask a question…` so the prompt doesn't imply that the model can see the screen;
- only block sending for malformed/empty Base URL or model, not for a blank API key.

This is sufficient onboarding.

---

# 44. What "done" looks like

A clean manual test should work like this:

1. Build and launch kk.
2. kk appears in menu bar, not Dock.
3. Open Settings.
4. Enter:
   - Base URL
   - API key if the provider requires one
   - vision-capable model
5. Close Settings.
6. Open a webpage or code editor.
7. Put the mouse on that display.
8. Press `⌘⌥K`.
9. If access is missing, kk shows `Screen access needed`; click `Grant access` to trigger the system request. It does not request permission automatically on launch or invocation.
10. After permission is available, press `⌘⌥K` again if needed.
11. kk appears near the top center of that display immediately.
12. Prompt field is already focused while screen capture finishes in the background.
13. Type:
    `what is wrong here?`
14. Open `Screen attached` to inspect the exact image and destination, then close the preview.
15. Press Return.
16. Screenshot + prompt are sent to the configured provider. Removing `Screen attached` before this point instead sends only text.
17. Answer streams into the panel.
18. Markdown renders correctly while streaming.
19. A fenced code block looks like code.
20. `$x^2$`-style math renders as math.
21. Ask a follow-up without taking a new screenshot.
22. Follow-up answer preserves prior screen context.
23. Copy response works.
24. Press Escape.
25. Panel disappears.
26. Press `⌘⌥K` again.
27. A brand-new screenshot/session is used.

Also manually verify: typing during capture is uninterrupted; the prompt remains intact when permission is denied; Return during IME composition does not send; Shift-Return inserts a line; Escape closes an open screenshot preview before dismissing kk; scrolling up during streaming holds position; selecting answer text is not broken by auto-scroll; focus is not stolen when capture/streaming finishes; and the panel remains readable in light/dark, Increase Contrast, Reduce Motion, and on a short/narrow display. Verify VoiceOver can reach the screenshot preview, destination, and the Send/Stop controls. These are interaction checks on a Mac, not extra unit tests that mirror view code.

That is the v0.1 product.

---

# 45. Acceptance tests

Implement enough automated tests to catch low-level regressions where practical.

At minimum, unit-test pure logic.

## Base URL normalization

Inputs:

```text
https://api.openai.com/v1
https://api.openai.com/v1/
```

should both yield:

```text
https://api.openai.com/v1/chat/completions
```

An input already ending with:

```text
/chat/completions
```

must not duplicate the suffix.

## SSE parser

Given:

```text
data: {"choices":[{"delta":{"content":"Hel"}}]}

data: {"choices":[{"delta":{"content":"lo"}}]}

data: [DONE]
```

emits:

```text
Hel
lo
```

and completes normally.

It should ignore unrelated blank lines.

## Message serialization

With screenshot:
- first user content is multimodal
- exactly one image part exists
- MIME type is JPEG data URL

Without screenshot:
- user message can serialize as plain string

Follow-up:
- original screenshot appears only inside the first user turn
- prior assistant answer is preserved

## Authentication header

With a non-empty API key:
- request includes `Authorization: Bearer <key>`.

With an empty API key:
- request contains no `Authorization` header.

## Error decoding

A 401 produces `.unauthorized`.

A 429 produces `.rateLimited`.

A 500 produces `.server(...)`.

---

# 46. Build order

Implement in this order.

## Phase 1 — skeleton

- create macOS project
- menu bar app
- Settings window
- package dependencies
- preferences
- Keychain
- fixed global shortcut (`⌘⌥K`)

At the end:
- `⌘⌥K` can trigger a stub action.

## Phase 2 — panel

- custom `NSPanel`
- SwiftUI hosting
- positioning
- prompt editor
- focus
- Escape
- toggle with shortcut

At the end:
- `⌘⌥K`, type, Escape feels right.

## Phase 3 — capture

- display resolver
- ScreenCaptureKit
- self-app/window exclusion
- permission preflight/request path
- image resize/compression
- in-memory session screenshot
- capture state chip
- exact-image preview with destination disclosure and pre-send removal

At the end:
- invoking kk opens immediately and reliably captures the right display without capturing kk itself.

## Phase 4 — API

- request structs
- URLSession streaming
- SSE parser
- errors
- cancellation

Test first with text-only if necessary.

## Phase 5 — vision

- Base64 screenshot
- multimodal first user message
- full session reconstruction

## Phase 6 — rendering

- streaming Markdown
- code
- LaTeX
- scrolling
- copy

## Phase 7 — polish

- panel animation
- final spacing
- loading/stop states
- configuration states
- error copy
- dark mode
- cleanup
- keyboard/IME, VoiceOver, Reduce Motion/Transparency, light/dark, narrow-display checks from section 44

Do not start by polishing an elaborate visual design before capture + streaming work.

---

# 47. Implementation priorities

When tradeoffs arise, use this order:

1. reliability of invocation and keyboard focus
2. correct, inspectable screenshot context and explicit destination
3. low perceived latency
4. stable streaming and preserved reading/scroll position
5. readable and accessible Markdown/math
6. clean native appearance
7. secondary polish

A plain but instantaneous kk is better than a beautiful kk that fumbles focus or screenshot context.

---

# 48. Performance expectations

Reasonable targets on Apple Silicon:

- global shortcut response should feel immediate
- screenshot processing should generally complete in well under a second
- panel should appear immediately, while capture runs asynchronously
- no UI freeze while encoding screenshot
- streamed tokens should appear continuously
- Markdown rendering should remain smooth for normal answers
- memory from prior sessions should be released after dismissal

Never do Base64 encoding or large image work synchronously on the main thread if it causes visible stalls.

---

# 49. No premature abstraction

Do not create:
- provider protocol zoo
- plugin architecture
- agent architecture
- generic persistence layer
- dependency injection framework
- coordinator hierarchy
- Redux-like store
- elaborate design system
- giant reusable networking framework

Small protocols are fine when they improve testability, especially for:
- API key store
- screen capture
- API client

But keep the app small.

---

# 50. Small implementation decisions you are allowed to make

The implementation model may choose:

- exact Swift Observation vs ObservableObject usage
- exact `NSPanel` subclass details
- exact method to bridge focus into SwiftUI
- exact image resize helper implementation
- exact OSLog categories
- exact icons from SF Symbols
- exact padding values within a few points
- exact animation curve
- exact unit-test framework layout
- whether panel controller is created in AppDelegate or AppState
- whether SSE parsing is line-based or uses a tiny parser object

Do not change core product behavior while making these choices.

---

# 51. Things you should not "improve"

Do not decide to add these because they sound useful:

- prompt history
- persistent history
- screenshot gallery
- multiple screenshots
- region capture
- selected window capture
- voice input
- model picker dropdown populated from API
- provider presets
- clipboard context
- OCR
- text insertion
- agents
- coding tools
- file upload
- response regeneration
- branches
- model comparison
- token counters
- cost estimates

The whole point of kk is that the product stays tiny.

---

# 52. Reference implementation notes

Useful current APIs/packages:

## ScreenCaptureKit

Apple documentation:
- `SCShareableContent`
- `SCContentFilter`
- `SCScreenshotManager`

Reference:
`https://developer.apple.com/documentation/screencapturekit`

A current single-frame API is conceptually:

```swift
let image = try await SCScreenshotManager.captureImage(
    contentFilter: filter,
    configuration: configuration
)
```

Use the current SDK signature available in Xcode.

## KeyboardShortcuts

`https://github.com/sindresorhus/KeyboardShortcuts`

For v0.1 use:
- a hard-coded `KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])`
- `KeyboardShortcuts.events(for:)`
- toggle on key-up

Do not use `KeyboardShortcuts.Recorder` in v0.1.

## MarkdownView

`https://github.com/LiYanan2004/MarkdownView`

Use 3.x streaming support:
- `StreamingMarkdownSource`
- `StreamingMarkdownReader`
- `MarkdownView`
- `.markdownMathRenderingEnabled()`

Follow its current 3.x API rather than copying stale pre-3.0 examples.

---

# 53. Suggested constants

Centralize approximately:

```swift
enum UIConstants {
    static let panelWidth: CGFloat = 680
    static let panelMaxHeight: CGFloat = 620
    static let panelTopMargin: CGFloat = 88
    static let cornerRadius: CGFloat = 12
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let previewMaxWidth: CGFloat = 560
    static let previewMaxHeight: CGFloat = 360
    static let scrollFollowThreshold: CGFloat = 40
}

enum CaptureConstants {
    static let maxLongEdge: CGFloat = 2560
    static let jpegQuality: CGFloat = 0.85
    static let fallbackLongEdge: CGFloat = 2048
    static let fallbackJPEGQuality: CGFloat = 0.75
    static let softMaxBytes = 2_500_000
}

enum Defaults {
    static let baseURL = "https://api.openai.com/v1"
    static let model = "gpt-5.6-luna"
}
```

These are product defaults, not immutable law. Small technical adjustment is fine.

---

# 54. Suggested system prompt constant

```swift
static let systemPrompt = """
You are kk, a concise assistant answering questions using the user's screen as visual context. Answer the user's question directly. Pay close attention to visible text, UI, code, diagrams, math, and errors. Use Markdown when useful. For math, use `$...$` for inline math and `$$...$$` for display math. Do not describe the screenshot unless it helps answer the question.
"""
```

Do not add giant hidden prompts.

---

# 55. Known implementation constraints

These are known sharp edges, not invitations to redesign the app.

## Global hotkey

`KeyboardShortcuts` 3.x is appropriate for the global hotkey, but current macOS releases have had regressions around Option-only letter combinations and the package's Recorder UI. That is why v0.1 uses fixed `⌘⌥K` and no Recorder.

## Non-activating panel focus

AppKit non-activating panels can accept keyboard input, but SwiftUI/AppKit focus bridging is one of the highest-risk implementation details. Test the exact interaction:

```text
other app focused → ⌘⌥K → type immediately
```

If `.nonactivatingPanel` prevents reliable text focus, prefer a narrowly-scoped AppKit adjustment over adding Accessibility/Input Monitoring permissions. Do not introduce those permissions simply to solve focus.

## Screen capture permission

TCC behavior varies somewhat across macOS versions. Use the official preflight/request APIs, include `NSScreenCaptureUsageDescription`, and provide the System Settings escape hatch.

## OpenAI compatibility

"OpenAI-compatible" means the common `POST /chat/completions` message/SSE contract. Do not promise compatibility with servers that require custom authentication headers, proprietary request fields, or a different vision schema.

## Markdown

Model output is untrusted presentation content. Do not evaluate HTML/JavaScript and do not automatically fetch remote Markdown images.

---

# 56. Expected repository quality

Before considering implementation complete:

- project builds without warnings that indicate real bugs
- no force unwraps around networking/capture data unless unquestionably safe
- async cancellation works
- no API key in source
- no screenshot persistence
- no dead placeholder UI
- no obviously unused abstraction
- README explains setup and permissions
- dependency versions are pinned to sensible major versions
- app can be launched directly from Xcode and used end-to-end

---

# 57. README requirements

The repository README should be short.

Include:

```text
# kk

Native macOS screen-context Q&A.

Press ⌘⌥K, ask a question, and kk sends your prompt plus any attached screen image directly to an OpenAI-compatible model.
```

Then sections:
- Requirements
- Setup
- Permissions
- API configuration
- Build
- Privacy

Privacy should state:
- screenshots remain in memory;
- requests go directly to configured API provider;
- no analytics/history backend.

Do not write marketing copy.

---

# 58. Final instruction to the implementation model

Implement the complete v0.1 described here.

Do not stop after scaffolding.
Do not merely give code snippets.
Do not return a plan instead of implementation.

Work through the project until:

- it builds;
- the global shortcut works;
- screenshot capture works;
- the floating panel works;
- API requests stream;
- Markdown and LaTeX render;
- follow-ups work;
- Settings and Keychain work;
- the defined error states are handled.

When uncertain, prefer the simplest implementation that preserves the UX in this spec.

This document is self-contained. If the UI Design Suite skill is also supplied, use it only to decide unspecified visual details; its web page recipes, display-font suggestions, and generic component defaults do not override this native macOS contract.

Do not expand scope.

The product should feel like a very small native macOS utility whose entire purpose is:

> **⌘⌥K → ask about the screen → get the answer.**
