# PrismShift

**A native macOS utility for converting files from a Liquid Glass radial menu.**

Drag a file in Finder, tap **Shift**, and drop it onto an output format. PrismShift processes files locally and saves new copies beside the originals. It lives in the menu bar and also provides a file picker.

## Requirements

- macOS 14 or later.
- macOS 26 for native Liquid Glass; older systems use a translucent material.
- To build: Swift 6 tooling and the macOS 26 SDK, available with compatible Xcode or Command Line Tools.

## Build and run

~~~sh
git clone https://github.com/SrikarKorrapati/prismshift.git
cd prismshift
./build-app.sh
open "outputs/PrismShift.app"
~~~

The build script creates the app bundle and keeps compiler caches inside the repository. It does not launch the app automatically.

## Use

| Gesture | Result |
| --- | --- |
| Drag a file, then tap Shift | Show conversion formats at the pointer |
| Command during a drag | Show file tools |
| Control during a drag | Show file actions |
| Drop onto a segment | Run that action |
| Drop in the centre | Keep the files selected, then click an action |
| Arrow keys and Return | Select and run an action after opening the file picker |
| Escape | Dismiss the wheel |

Release Shift while continuing to drag; the wheel stays open until the drop finishes. You can also select **Choose Files…** from the menu-bar icon or click the small drop target. Click the success message to reveal the result in Finder.

## Supported operations

| Input | Operations |
| --- | --- |
| Images | JPG, PNG, HEIC, TIFF, BMP, single-frame GIF, PDF, 50% pixel resize |
| PDF | All pages to JPG/PNG at 300 DPI, selectable text to TXT, split, merge |
| Compatible video | MP4, MOV, audio extraction to M4A |
| Compatible audio | M4A |
| Any file | Reveal in Finder, copy path |

HEIC and media conversion depend on the encoders and codecs available in macOS. Page exports are grouped into a new folder. Repeated conversions receive distinct output names; originals are preserved.

## Architecture

| Component | Responsibility |
| --- | --- |
| [App entry point](Sources/PrismShift/main.swift) | App lifecycle, menu bar, file-opening events, keyboard menus |
| [Drag monitor](Sources/PrismShift/DragMonitor.swift) | Public mouse/modifier state and fresh drag-pasteboard detection |
| [Drag gesture gate](Sources/PrismShift/DragGestureGate.swift) | Movement threshold and stale-payload rejection |
| [Window controller](Sources/PrismShift/MainWindowController.swift) | Nonactivating panel, drag/drop callbacks, file selection, action dispatch |
| [Glass wheel](Sources/PrismShift/GlassWheelView.swift) | Native glass segments, shared geometry for rendering and hit testing, accessibility |
| [Action catalogue](Sources/PrismShift/FileAction.swift) | Available actions for each file type and wheel mode |
| [Conversion service](Sources/PrismShift/ConversionService.swift) | ImageIO, PDFKit, and AVFoundation conversion on a serial worker actor |

The drag monitor uses public state polling rather than a global keyboard event tap. A pointer movement threshold and fresh file payload prevent ordinary clicks from reopening a previous drag. The controller delays dismissal after mouse-up so AppKit can deliver the drop callback.

## Verification

~~~sh
./test.sh
~~~

The smoke tests generate their own fixtures under `work/` and verify:

- Action selection and rounded-segment hit testing.
- Drag movement thresholds, ordinary clicks, and stale payload rejection.
- Image encoding, dimensions, resize, and images-to-PDF.
- PDF page count, 300 DPI export, rotation, text extraction, split, and merge.
- Distinct output names, partial batch failures, and unchanged originals.

For media checks, install FFmpeg separately and run:

~~~sh
./test.sh --media
~~~

This generates a short synthetic video and verifies that MP4, MOV, and M4A outputs have playable tracks. FFmpeg is only used to make the test input; the app uses AVFoundation.

## Current limits

PrismShift is an independent prototype inspired by Tangerine. It does not yet implement the original app's full conversion catalogue, document conversions, OCR, or advanced editors. GIF output contains one frame. PDF pages exceeding 80 megapixels at 300 DPI produce an error rather than exhausting memory.

Automated tests cover conversion results and interaction logic. The Finder drag gesture and exact compositor appearance still require desktop verification; visual parity with the reference reel is not claimed.

## References

- [Tangerine](https://www.tangerineformac.com/) — interaction and visual reference.
- [ZestDrop](https://github.com/Maxaccurate/ZestDrop/tree/0561d01ce3d64b4d3142be24f1a6e3e68015c7dd) — architecture reference for drag tracking, action catalogues, and background conversion. Its movement threshold and delayed dismissal informed the independent Swift implementation. No Windows source or runtime is bundled.

Build products, local test fixtures, screenshots, and downloaded reference code are excluded from Git.
