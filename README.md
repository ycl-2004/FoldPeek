<p align="center">
  <img src="FoldPeekApp/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="FoldPeek logo" width="120" height="120">
</p>

<h1 align="center">FoldPeek</h1>

<p align="center">
  <strong>Browse a folder as a read-only paper index directly inside Finder Quick Look.</strong>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/FoldPeek/releases/latest"><img src="https://img.shields.io/github/v/release/ycl-2004/FoldPeek?label=release&color=111111" alt="Latest release"></a>
  <a href="https://github.com/ycl-2004/FoldPeek/releases"><img src="https://img.shields.io/github/downloads/ycl-2004/FoldPeek/total?label=downloads&color=111111" alt="Total downloads"></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-111111?logo=apple&logoColor=white" alt="macOS 13.0 or later">
  <img src="https://img.shields.io/badge/Mac-Universal%202-111111?logo=apple&logoColor=white" alt="Universal app for Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" alt="Built with SwiftUI and AppKit">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-111111" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://github.com/ycl-2004/FoldPeek/releases/latest/download/FoldPeek.zip"><strong>⬇ Download for macOS</strong></a>
  ·
  <a href="https://github.com/ycl-2004/FoldPeek/releases">Releases</a>
  ·
  <a href="#features">Features</a>
  ·
  <a href="#privacy-and-security">Privacy &amp; security</a>
  ·
  <a href="#build-from-source">Build from source</a>
  ·
  <a href="#license">License</a>
</p>

Select a folder in Finder and press **Space**. FoldPeek replaces the
plain folder preview with a bounded, expandable index and an inspector for text,
code, Markdown, PDF, Word documents, images, and file metadata. It stays inside
Quick Look—there is no separate file-manager window to keep open.

FoldPeek is intentionally narrow. It previews folders read-only, performs no
network requests, launches no external tools, and stores no folder contents.
The host app exists only to explain how to enable the Quick Look extension.

> **Current distribution status:** the public Universal 2 build is ad-hoc
> signed and not Apple-notarized. macOS therefore requires explicit trust on
> first launch. The release supports Apple Silicon and Intel Macs; the complete
> source remains available for review and local builds.

## Quick start

1. **[Download `FoldPeek.zip`](https://github.com/ycl-2004/FoldPeek/releases/latest/download/FoldPeek.zip)**
   and unzip it.
2. Move `FoldPeek.app` to `/Applications`.
3. Clear the quarantine flag—the public build is ad-hoc signed, not notarized:

   ```bash
   xattr -dr com.apple.quarantine /Applications/FoldPeek.app
   ```

4. Open **System Settings → General → Login Items & Extensions → Quick Look** and enable **FoldPeek**.
5. Select a folder in Finder and press **Space**.

### System requirements

- macOS 13.0 or later
- Apple Silicon (`arm64`) or Intel (`x86_64`) Mac
- No account, package dependency, or network connection required at runtime

The current public release is
[`v1.0.0`](https://github.com/ycl-2004/FoldPeek/releases/tag/v1.0.0), built
from project version `1.0 (build 1)` and verified with Xcode 26.6.

## Why FoldPeek

- **Stay in Finder.** Inspect a directory without opening another window or
  losing the file you already selected.
- **Read only by construction.** The extension has user-selected read-only file
  access and contains no rename, delete, move, clipboard, or file-launch path.
- **Load only what you ask for.** The first level appears immediately;
  subfolders are read only when you expand them, and search never triggers a
  directory read.
- **Treat source as source.** Code uses a bounded, single-pass syntax scanner;
  Markdown uses an inert in-process renderer rather than HTML or a document
  engine.
- **Never guess a document reader.** Word, RTF, and OpenDocument files name the
  exact AppKit reader to use, so no file can steer itself into the HTML path.
  Formats FoldPeek cannot read are drawn by Apple's own thumbnail service, out
  of process, rather than parsed here.
- **Keep hostile inputs bounded.** Directory enumeration, tree size, preview
  bytes, image dimensions, syntax coloring, and Markdown layout all have hard
  limits in code.

## Features

**Folder index**

- Groups the folder's own contents by kind — folders, documents, sheets,
  slides, images, video, audio, code, text, data, archives — each under a
  headed rule in its own colour, with names sorted naturally inside the group.
- Prints a legend strip of every group present, which doubles as a jump target
  for reaching a group without scrolling to it.
- Colours each row's extension chip by category, so a long list can be scanned
  by kind without reading a filename.
- Expands and collapses a folder from anywhere on its row.
- Loads one level at a time, with a shared per-panel item budget and depth cap.
- Shows symbolic links as entries but does not intentionally traverse them.
- Filters by name across the nodes already loaded and reveals matching paths.

**File inspector**

- Shows kind, size, modification date, symbolic-link state, and path, with the
  header badge carrying the item's category colour.
- Previews bounded UTF-8 text in a non-editable `NSTextView`.
- Adds line numbers, indentation guides, syntax colors, and bracket-depth colors
  for common source formats.
- Lays out a safe Markdown subset: headings, lists, tables, quotes, emphasis,
  rules, and fenced code.
- Scrolls multi-page PDFs through PDFKit, with link annotations disarmed so a
  click never opens a browser.
- Re-types Word (`.doc`, `.docx`), RTF, and OpenDocument text onto the paper
  surface, keeping structure and dropping the document's own fonts and links.
- Decodes supported images through ImageIO into a thumbnail capped at 2,048 px.
- Recovers the first-page picture Pages, Keynote, Numbers, and some Office
  files already carry inside them, read in process and without a document
  parser.
- Reads an Excel workbook's sheets as ruled tables, with a tab per sheet and a
  toggle between the page image and the data — a twenty-sheet file is nineteen
  sheets more than any single picture of it can show.
- Falls back to Apple's thumbnail service for everything else — PowerPoint,
  legacy Office, Keynote files with no embedded picture — which needs one named
  sandbox exception, described in the security notes.
- Falls back to metadata for unsupported or non-regular files.

**Paper interface**

- Fixed cream paper, wine identity accents, denim structure, serif prose, and
  monospaced technical details.
- Resizable index and content panes inside the Quick Look panel.
- A deliberately fixed light palette rather than automatic Dark Mode styling.

## How it works

```text
Finder selection
      │
      ▼
Quick Look Extension
      │
      ├── bounded one-level directory enumeration
      ├── lazy expandable index + in-memory filter
      └── capped text, Markdown, PDF, document, or image preview + metadata
```

The extension registers only `public.folder` and `public.directory`. It holds
security-scoped access while the preview panel is alive because file and
subfolder reads happen after the initial preview request, then releases that
access when the panel goes away.

## Privacy and security

FoldPeek has no accounts, analytics, advertising, telemetry, update service, or
runtime network access. It does not persist folder listings or previewed file
contents.

The checked-in entitlements are intentionally small:

| Target | Entitlements |
| --- | --- |
| Host app | `com.apple.security.app-sandbox` |
| Quick Look extension | App Sandbox + `com.apple.security.files.user-selected.read-only` |

The current bounds are enforced in source:

| Bound | Limit |
| --- | ---: |
| Entries per directory | 2,000 |
| Total entries per preview panel | 20,000 |
| Expansion depth | 8 levels |
| Text read per file | 256 KB |
| Image file accepted | 64 MB |
| Decoded image edge | 2,048 px |
| PDF file accepted | 512 MB |
| Word/RTF/OpenDocument file accepted | 32 MB |
| Characters laid out from a document | 400,000 |
| Workbook rows per sheet | 400 |
| Workbook columns per row | 32 |
| System page render accepted | 512 MB |
| System page render timeout | 8 s |
| Characters syntax-colored | 200,000 |
| Characters laid out as Markdown | 200,000 |

Text stays inert: rich text, graphics import, data detectors, clickable links,
and text attachments are disabled. Images are decoded through ImageIO at a
bounded pixel size. PDF pages are drawn by PDFKit with link annotations and data
detectors turned off. Word, RTF, and OpenDocument files are read by AppKit with
the document type stated rather than sniffed, and arrive stripped of their own
links. Supported Office containers are parsed only for bounded embedded previews
and workbook sheets; every other format is rendered by the system thumbnail
service in Apple's process, never parsed here. Standalone archive browsing,
HTML, SVG, subprocesses, external applications, and background helpers remain
outside this edition's scope.

See [`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md) for the trust boundaries,
enforced capabilities, verification checklist, and residual-risk notes.

## Current release

FoldPeek `v1.0.0` is the first public macOS release. The app is a Universal 2
build containing native `arm64` and `x86_64` executables for both the host and
Quick Look extension.

| Artifact | Purpose |
| --- | --- |
| `FoldPeek.zip` | Ad-hoc signed Universal 2 app for macOS 13.0 or later |
| `FoldPeek.zip.sha256` | SHA-256 checksum for download verification |

Verify the download from the directory containing both files:

```bash
shasum -a 256 -c FoldPeek.zip.sha256
```

## FAQ

<details>
<summary>Why does search ignore files inside a folder I have not opened?</summary>

Search is deliberately limited to nodes already loaded. A keystroke never walks
the directory tree, so filtering cannot bypass the depth and item budgets or
cause unexpected disk activity.

</details>

<details>
<summary>Why do the arrow keys switch Finder selections instead of moving through the index?</summary>

Finder owns those keys while its Quick Look panel is active. Use the pointer to
select and expand rows inside FoldPeek.

</details>

<details>
<summary>How do I uninstall FoldPeek?</summary>

Turn off **FoldPeek** under **System Settings → General → Login Items &
Extensions → Quick Look**, then move `FoldPeek.app` to the Trash. FoldPeek does
not install a helper, LaunchAgent, login item, or shared preference store.

</details>

<details>
<summary>Can I send someone a built copy?</summary>

Share the public
[`v1.0.0` release](https://github.com/ycl-2004/FoldPeek/releases/tag/v1.0.0)
together with [`INSTALL.md`](INSTALL.md). The build is ad-hoc signed and not
notarized, so the recipient must explicitly trust it and clear macOS quarantine
before opening it.

</details>

## Build from source

<details>
<summary>Requirements, build verification, and signing notes</summary>

Requirements:

- macOS 13.0 or later
- Xcode 15 or later
- No Swift Package Manager dependencies
- No configured Apple Developer Team in the shared project

Open `FoldPeek.xcodeproj`, choose the `FoldPeek` scheme and **My
Mac**, then build or run. If Xcode requests signing configuration, choose your
own Team or use the unsigned verification command below.

Verify a Release build without a signing identity:

```bash
xcodebuild -project FoldPeek.xcodeproj \
  -scheme FoldPeek \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FoldPeekDerivedData \
  SYMROOT=/tmp/FoldPeekBuild \
  OBJROOT=/tmp/FoldPeekIntermediates \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The repository does not currently contain an automated test target. The Release
build and Xcode static analysis are the available automated verification paths.

The manual packaging script performs a clean Universal 2 Release build,
re-signs the host and extension with the repository entitlements, verifies the
bundle signature, and writes `dist/FoldPeek.zip` and
`dist/FoldPeek.zip.sha256`. It does not install the app, modify `/Applications`,
register the extension, restart Finder, or download tools.

</details>

## Project layout

- `FoldPeekApp/` — SwiftUI onboarding host, app entitlements, and visual assets.
- `FoldPeekPreviewExtension/` — Quick Look controller, index UI, source/Markdown/workbook rendering, and inspector views.
- `Shared/` — file metadata, bounded directory loading, file preview loading, ZIP/XML helpers, and workbook reading.
- `FoldPeek.xcodeproj/` — the two-target Xcode project.
- `docs/DEVELOPMENT.md` — architecture, invariants, bounds, and verification guidance.
- `docs/SECURITY_AUDIT.md` — current trust boundaries, limits, and residual risks.
- `scripts/package.sh` — manual ad-hoc packaging for direct sharing.
- `artwork/` — source artwork used to generate the checked-in app icon set.

## Versioning and releases

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`FoldPeek.xcodeproj/project.pbxproj` are the version sources of truth for
both targets. The current source is `1.0 (build 1)`.

Public releases use `v<version>` tags and attach stable `FoldPeek.zip` and
`FoldPeek.zip.sha256` filenames. Future releases should bump both targets
together and state their signing and notarization status explicitly.

## Known limitations

- Ad-hoc packages are not Apple-notarized and require manual trust on another Mac.
- Search covers only nodes already loaded into the current preview panel.
- Finder keeps ownership of arrow-key navigation while Quick Look is open.
- The paper palette is intentionally light and does not follow Dark Mode.
- Bounded text, Markdown, PDF, word-processing documents, supported raster
  images, and supported XLSX/XLSM workbooks receive content previews.
- Directory, tree, text, image, document, PDF, workbook, highlighting, and
  Markdown limits are fixed.
- The Xcode project currently has no automated test target or CI workflow.

## License

FoldPeek is copyright © 2026 YC and available under the [MIT License](LICENSE).
