# FoldPeek security audit

Audit date: 2026-08-31

## Scope

This audit covers the source, entitlements, Xcode project, and manual packaging
flow checked into this repository. It describes FoldPeek's current security
properties; it does not claim that an arbitrary binary was built from this
source.

FoldPeek consists of:

- A sandboxed SwiftUI host that only explains how to enable the extension.
- A sandboxed Quick Look extension registered for folders and directories.
- Native AppKit, Foundation, Uniform Type Identifiers, ImageIO, PDFKit, and
  QuickLookThumbnailing code.
- No package-manager dependencies or vendored executables.

## Trust boundaries

Finder provides the selected directory URL to the Quick Look extension. The
extension obtains security-scoped, read-only access while its preview panel is
alive and releases that access from `deinit`.

Names, metadata, text bytes, image bytes, Markdown, PDF pages, and document
bodies are untrusted input. The UI displays them but must not treat them as
commands, URLs to follow, or paths to open.

Two of the readers are Apple's rather than this project's. AppKit reads Word,
RTF, and OpenDocument files in process; the system thumbnail service renders
every remaining format out of process, in Apple's own sandbox, and returns a
bitmap. Neither is given a choice about which reader to use — see below.

## Enforced capabilities

The host entitlement file contains only:

- `com.apple.security.app-sandbox`

The preview extension adds only:

- `com.apple.security.files.user-selected.read-only`
- `com.apple.security.temporary-exception.mach-lookup.global-name`, naming the
  single service `com.apple.quicklook.ThumbnailsAgent`

The mach-lookup exception exists because an app extension's sandbox is stricter
than an app's and denies the XPC connection `QLThumbnailGenerator` requires:
every request fails with `NSXPCConnectionInvalid` (4099) before a file is ever
considered. It names one Apple service, grants no network access, and does not
widen the file access above.

The extension's `Info.plist` registers only `public.folder` and
`public.directory`.

Repository scans and the Xcode project should remain free of network
entitlements, Apple Events, automation, accessibility, broad filesystem access,
login items, LaunchAgents, URL schemes, and shell-script build phases.

## Directory handling

`DirectoryScanner` coordinates a read and scans one directory level at a
time. Enumeration skips hidden files, package descendants, and subdirectory
descendants. Expansion happens only after an explicit row action.

Symbolic links are represented as entries but never treated as traversable
directories. The selected root is also rejected when it is a symbolic link.

Hard bounds:

| Resource | Limit |
| --- | ---: |
| Entries per directory | 2,000 |
| Entries per preview panel | 20,000 |
| Expansion depth | 8 levels |

Search operates only on nodes already in memory. Typing in the search field
does not read another directory.

## File preview handling

Only regular files can enter the preview loaders. Symbolic links, directories,
sockets, FIFOs, and device nodes are refused.

Text is read through a bounded `FileHandle` operation. The text view is
non-editable and disables rich-text import, graphics import, automatic links,
and data detectors.

Images are rejected above the file-size cap, then decoded through ImageIO into
a thumbnail with a bounded edge length. The original full-resolution image is
not retained for display.

PDF files are rejected above the file-size cap, then opened with PDFKit. An
encrypted document is refused rather than unlocked: FoldPeek never prompts for
a password. The view disables data detectors, and its delegate implements
`pdfView(_:clickedLink:)` as an empty method, which is what prevents PDFKit from
opening a link annotation's URL — its default behaviour when no delegate claims
the message. The delegate is a dedicated object rather than the PDF view
itself: on current macOS, PDFView reading its own weak delegate during a scale
change crashes, so FoldPeek never makes the view its own delegate.

Word, RTF, and OpenDocument files are read by `NSAttributedString` with
`.documentType` stated explicitly from the file extension. This is the security
control, not a convenience: without it, `NSAttributedString` infers the reader
from the bytes and can select the WebKit-backed HTML reader, which loads remote
resources. The result is then stripped of `.link`, `.toolTip`, and `.cursor`
attributes, re-typed into the project's own faces, and has attachment sizes
capped.

Pages, Keynote, Numbers, and some Office files are ZIP containers that already
store a rendered picture of their first page. `ZipArchive` reads the container's
central directory once, capping its size, its entry count, and every entry it
records. `ContainerPreviewReader` then asks for that one picture by exact name
and decodes it through ImageIO.

A workbook is the one document kind the page image cannot serve: a twenty-sheet
file has nineteen sheets no picture of the first will ever show. `WorkbookReader`
therefore reads four entries by exact name — the workbook, its relationships,
the shared string table, and one worksheet at a time — and turns cells into
strings. No formula is evaluated, no relationship target is resolved as a
filesystem path, and no cell's text is ever treated as markup.

Both readers parse XML with `XMLScanner`, a forward-only scanner written for
this purpose. It recognises elements, attributes, character data, CDATA, and the
five predefined entities. It has no DTD support and defines no entities, so a
declared entity is skipped rather than expanded and the expansion attacks a
general parser must defend against have nothing here to work on.

Every remaining format is handed to `QLThumbnailGenerator` as a URL. Only
`.thumbnail` is requested, never an icon representation, so a generic document
icon is never shown as though it were content. The request is cancelled after
its timeout so a stuck service cannot hold the pane.

### A rejected approach

Lending the service a hard link, or a copy-on-write clone, inside this
extension's own container was implemented and then removed. Instrumentation
showed the clone succeeded and the render still failed with the same 4099: the
barrier was never file access, so the copy bought nothing, and it was deleted
along with the security property it would have cost.

| Resource | Limit |
| --- | ---: |
| Text bytes | 256 KB |
| Image file | 64 MB |
| Decoded image edge | 2,048 px |
| PDF file | 512 MB |
| Word/RTF/OpenDocument file | 32 MB |
| Characters laid out from a document | 400,000 |
| System page render file | 512 MB |
| System page render timeout | 8 s |
| Container preview entry inflated | 32 MB |
| Container central directory read | 8 MB |
| Container entries recorded | 8,192 |
| Workbook rows per sheet | 400 |
| Workbook columns per row | 32 |
| Workbook characters per cell | 240 |
| Workbook shared strings | 200,000 |
| Syntax-highlighted characters | 200,000 |
| Markdown-rendered characters | 200,000 |

## Inert rendering

`CodeHighlighter` and `MarkdownRenderer` are forward-only scanners over the
already bounded string. They do not execute code, use a web view, launch an
application, or resolve a reference found in the file.

Rendered Markdown never emits a `.link` attribute or an
`NSTextAttachment`. Link destinations stay visible text and image references
stay placeholders. HTML is not interpreted.

The document and PDF surfaces hold the same line by a different means: they
inherit clickable content from Apple's readers and then take it away — link
attributes removed from the attributed string, link clicks swallowed in the PDF
view. No path in this project opens a URL or launches an application. A
sandboxed Quick Look extension cannot: both `NSExtensionContext.openURL` and
`NSWorkspace.open` were measured returning false and launching nothing, the
latter even with a LaunchServices mach-lookup exception in place.

## Packaging

`scripts/package.sh` is manual and project-local. It builds a Universal 2
Release app, re-signs the host and extension with the checked-in entitlements,
rejects `get-task-allow`, verifies the bundle signature, and writes a ZIP plus
SHA-256 checksum.

The script does not install the app, modify `/Applications`, restart Finder,
register the extension, download a tool, or create a persistent hook.

The public build is ad-hoc signed and not notarized. Clearing quarantine is an
explicit trust decision, which `INSTALL.md` states before showing the command.

## Residual risks

- ImageIO, PDFKit, AppKit's document readers, and macOS filesystem metadata
  parsing remain native parser surfaces. PDF and Word parsing are the largest of
  them, and both run in this process.
- The system thumbnail service runs out of process, but a file that reaches it
  is being parsed by whichever generator macOS has registered for that type,
  including third-party ones.
- The mach-lookup exception is a hole in the sandbox, narrow but real: this
  extension may address one Apple service that a default app extension may not.
- `ZipArchive`, `XMLScanner`, and `WorkbookReader` are hand-written parsers
  operating on untrusted bytes. Each is bounded on every dimension the file
  controls, and the XML scanner cannot expand an entity by construction, but
  they are parser code and carry a parser's risk.
- Reading a workbook's sheets means enumerating the container's entry table,
  which an earlier edition of this extension did not do.
- A slow or remote volume can make an explicitly requested expansion pause.
- Adversarial names can still impose bounded layout and comparison work.
- The Markdown implementation is intentionally partial; unsupported syntax is
  displayed literally.
- The fixed light palette does not follow Dark Mode.
- An ad-hoc signature proves integrity after signing, not publisher identity.
- The project has no automated test target or reproducible-build attestation.

## Verification checklist

- Parse the project with `xcodebuild -list -project FoldPeek.xcodeproj` and
  compare its internal workspace file with Xcode-generated project workspaces.
- Build Release with signing disabled into temporary output directories.
- Run the manual packaging script and verify its entitlement-count gate.
- Inspect built host and extension bundle identifiers with `PlistBuddy`.
- Confirm both executables contain `arm64` and `x86_64`.
- Scan tracked text for forbidden capabilities and stale project identities.
- Compare repository blobs and source blocks against any reference repository
  when provenance or source-independence is being assessed.
