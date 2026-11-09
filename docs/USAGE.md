# Using kk

[Back to README](../README.md)

## Screen context

In **Settings → General → Attach screen**, choose the display under the cursor (default), the active window's display, or all displays. All-displays mode attaches a separate image for each visible desktop; it does not capture hidden macOS Spaces. Drawing and freezing apply to the display where kk opens.

Use the screen icon beside the question field to preview attached images. Right-click it to remove the screen for that turn. Hiding the preview control in Settings does not remove the attachment.

With **Settings → Annotations → Freeze screen** enabled, kk holds a snapshot behind your marks. Pointer mode temporarily reveals the live desktop and lets clicks pass through. Selecting a drawing tool returns to the frozen snapshot. With freezing off, kk refreshes the selected screens when you send.

Each completed answer starts a new annotation session for the next question. Follow-ups can refer to a different screen; previous turns retain their original attachments. Retry reuses the failed question's images. A capture failure preserves your draft and marks rather than sending a partial set of displays.

## Attachments

Attach files to any question, in the launcher or in a follow-up:

- **Paste** with **⌘V**: a file copied in Finder, a screenshot copied with **⌘⌃⇧4**, an image copied from a browser, or pages copied from Preview. Copied text still pastes as text.
- **Drop** files or images anywhere on kk. The question field blurs and shows a drop target while you drag. Photos dragged from the Photos app work too; macOS copies them to a private temporary folder, which kk deletes as soon as it has read them.
- **Pick** files with the paperclip button. It's hidden by default; turn it on in **Settings → Advanced → Show attach button**.

Supported files:

| Type | What kk sends |
| --- | --- |
| Images: PNG, JPEG, HEIC/HEIF, WebP, GIF, TIFF, AVIF, and other formats macOS can read | A JPEG, downscaled to at most 2560 pixels on the long edge. Photos are rotated upright, and transparent areas become white. |
| PDFs | The text of every page (up to 300 pages). Scanned pages without a text layer are read with on-device OCR (up to 40 pages per PDF). By default, the first 8 pages are also sent as images so vision models can see figures and layout. |
| Text files: `.txt`, `.md`, `.py`, `.json`, `.csv`, source code, and other plain text | The text, decoded from UTF-8, UTF-16 or UTF-32 (with or without a byte-order mark), or Windows-1252. |

Each question can carry up to 10 attachments. Text and PDF text longer than 150,000 characters is truncated, and the model is told. Click a chip to preview what will be sent; click × to remove it. Sending waits until every attachment has finished loading. A file kk can't read shows an error on its chip and isn't sent.

Attachments stay with their question, so follow-ups can refer back to them. Retry resends the same attachments.

**Settings → Advanced** controls:

- **Send attachments without a question** (on by default). Press Return with only attachments and kk summarizes them.
- **PDF page images**: off, or the first 4, 8 (default), or 16 pages. Turn page images off for text-only models or to send less data. PDF text is always sent.

Images and PDF page images need a vision-capable model. Text files and PDF text work with any model.

## Annotations

Choose a tool from the palette or use its shortcut while the canvas has focus:

| Key | Tool / action |
| --- | --- |
| V | Pointer: interact with the desktop |
| F | Freehand |
| E | Ellipse / circle |
| R | Rectangle |
| A | Arrow |
| X | Eraser: click to remove a whole stroke |
| Space | Focus the question field |
| Delete | Remove the hovered annotation |

Drag near a mark's stroke to move it. Hover rectangles and ellipses to reveal corner resize handles; arrows have endpoint handles. Undo restores moves, resizes, and deletions. Handles are excluded from submitted screenshots.

Double-tap Shift in the question field to return to drawing, or click the pencil button in a conversation. Change or disable this gesture in **Settings → Annotations**. That section also controls activation, default tool and color, line weight, smoothing, tool shortcuts, palette position, hover deletion, and discard confirmation. Double Shift may overlap with macOS Sticky Keys.

## Conversations and copying

**Return** sends; **Shift+Return** adds a line. While an answer streams, you can edit the next draft or click **Stop**. Scrolling up pauses automatic following; return to the bottom to resume it. Pressing the global shortcut during an existing chat focuses the follow-up field.

Each answer has a **Copy** action. In **Settings → Shortcuts**, optionally make **⌘C** copy the latest answer or copy and close. Selected text keeps normal copy behavior.

**Settings → Advanced** offers confirmation before dismissing a multi-turn chat and copying the chat as Markdown on dismissal. Both default to off and apply after at least two user questions. Transcripts include questions, answers, and attachment names, without screenshots, attachment contents, or model thinking. Conversations are not saved automatically.

## Appearance and placement

Drag the header to move kk, and resize from an edge or corner. **Settings → General** controls compact/full opening size, width, placement at the default position or cursor, material, appearance, accent, and answer text size. **Settings → Advanced** controls snapping, always-on-top behavior, and which buttons appear beside the question field. Liquid Glass requires macOS 26; earlier systems use translucency.

Enable **Move chat to largest blank space** to scan the chat’s display when it opens and whenever you send a message. kk looks for the largest visually quiet square, including whitespace inside other apps, and ignores faint thin dividers. Width stays within your configured opening width; both width and height shrink as needed, with a readable minimum that can overlap nearby content when space is tight. Once a message is sent, chat fills the available blank height above and below the square anchor, even beyond the usual 620-point height limit. Answers scroll within that space. Dragging or resizing takes control until the next send. This is a visual heuristic, so review its placement on busy or changing screens.

Placement scans require existing **Screen Recording** access, exclude kk’s own windows, stay in memory, and are never attached to a message or sent to your provider. If access or a useful blank area is unavailable, kk keeps its normal placement. The option is off by default and takes precedence over the normal opening-position choice.

Optional **Show model thinking** displays reasoning or summaries supplied by your endpoint. Availability depends on the provider and model. Thinking stays separate from answer copies and follow-up requests.

**Settings → About** contains launch at login and **Show onboarding again**. **Restore defaults** in General or Advanced resets only that tab, and preserves your connection and global shortcut.

## Troubleshooting

### kk opened, but no main window appeared

kk is a menu-bar app. Use its menu-bar icon or **⌘⌥K** to open the popup. When Settings is open, kk also shows a Dock icon.

### The screen is not attached

Click **Grant access**, then enable kk in **System Settings → Privacy & Security → Screen & System Audio Recording** (the label varies by macOS version). The helper can supply the running app's icon for dragging into the list. If macOS offers **Quit & Reopen**, use it. Otherwise quit and reopen kk if access is still unavailable. Text-only questions remain available.

### The API rejects a request

Check the base URL, model ID, and saved key in **Settings → Connection**. kk appends `/chat/completions` unless the URL already ends with it. The endpoint must support streaming Chat Completions and image input for screen questions. An OpenAI-compatible label alone does not guarantee that every provider supports the same features.

### Remove a saved API key

Use **Settings → Connection → Clear**. This leaves other preferences intact. You can also remove just kk's Keychain entry:

```sh
security delete-generic-password -s dev.kw2.kk -a openai-compatible-api-key
```

### An attachment won't load

The chip explains the problem. Folders, archives, apps, and binary files can't be attached; convert documents such as `.docx` to PDF or text first. Password-protected PDFs must be unlocked and saved without a password. The first scanned PDF after installing or updating macOS can take a minute while macOS prepares its text-recognition model; later PDFs take well under a second per page.

If the provider rejects a request with attachments, check that the model accepts images, or set **PDF page images** to **Off** for PDFs.

For other problems, [open an issue](https://github.com/imapotatoes11/kk/issues) with your macOS version, kk version, and reproduction steps. Remove keys and private screen content from any attachments.
