# README previews

These assets are **staged native UI renders**, not a recording of a live model session. The editor, academic problem set, and responses are fixtures. The popup, question editor, conversation, Markdown/code/LaTeX rendering, and annotation toolbar use kk's production views. The Python example explains a shared mutable default argument. The calculus example shows a white academic PDF scrolled to Problem 5 on page 2, evaluates its logarithmic integral, then moves and resizes the annotation to a specific case for a follow-up.

No personal screen is captured, no API request leaves the process, and no real API key is read. A local `URLProtocol` supplies deterministic streaming-format responses to the real chat controller. This demonstrates the screen-question and follow-up UI; it does not validate model vision or end-to-end screen capture.

## Regenerate

Requires the same macOS/Xcode environment as kk and a logged-in desktop session. Install `ffmpeg` if you also want to regenerate the GIF.

From the repository root:

```sh
Scripts/render-previews.sh
```

The script copies the current source and the authoring fixture into a temporary package under `DerivedData`, renders the PNGs into `docs/screenshots`, and builds two GIFs. Every scene, including the last, lasts two seconds: six seconds for coding and eight seconds for math. It removes the temporary package on exit and retains the Swift build cache under `DerivedData/DocumentationPreviewBuild`. Set `KK_PREVIEW_BUILD_PATH` to use a different build cache.

| Asset | Content |
| --- | --- |
| `annotate.png` | Question draft, circled code, and native annotation palette |
| `screen-context.png` | First answer with an attached staged screen and a follow-up draft |
| `follow-up.png` | Two-turn conversation with corrected code |
| `screen-context-dark.png` | First answer in dark appearance |
| `workflow.gif` | Coding: annotation → question → follow-up |
| `math-annotate.png` | Academic PDF scrolled to the integral problem, with the original ellipse annotation |
| `math-context.png` | First answer with native LaTeX rendering |
| `math-reannotate.png` | Original ellipse moved and resized to the n = 2 case, with a follow-up draft |
| `math-follow-up.png` | Follow-up answer with the evaluated result, using the changed screen attachment |
| `math-workflow.gif` | Math: annotation → answer → modified annotation → follow-up |

The background editor and PDF window chrome are mockups on a very light, muted pastel background. The PDF contents come from the actual two-page [problem-set.pdf](problem-set.pdf), drawn with PDFKit inside a native scroll view. The viewport is scrolled partway through the second page. Red ellipses use kk's annotation renderer and are included in the staged attachments. The math follow-up changes the original mark through the annotation document's transform operation and sends a different image on the second turn. The fixture checks that both turns retain their respective images, the PDF loads, and native answer math labels parse without errors. The app uses an opaque surface and the system accent. Dark appearance is applied to kk while the staged editor stays light, as separate apps can have different appearances. Images contain only windows and annotations; sample-content labels live in the README. The earlier standalone UI crops remain available in `docs/screenshots` but are not used in the refreshed README.

To edit the problem-set fixture, run `python3 docs/previews/make-problem-set.py` with `reportlab`, `matplotlib`, and `pypdf` installed, then regenerate the previews. It uses Computer Modern text and vector LaTeX-style math, without requiring a TeX installation. The checked-in PDF is sufficient for normal preview regeneration.

Review the PNGs at the README's displayed width after regeneration. Check text wrapping, the full code block, math, annotation alignment, the composer, and both appearances. The GIFs are inside collapsed README sections so they do not animate on initial load; the main preview is static.
