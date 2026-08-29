# FoldPeek security audit

Audit date: 2026-08-29

## Scope

This audit covers the source, entitlements, Xcode project, and manual packaging
flow checked into this repository. It describes FoldPeek's current security
properties; it does not claim that an arbitrary binary was built from this
source.

FoldPeek consists of:

- A sandboxed SwiftUI host that only explains how to enable the extension.
- A sandboxed Quick Look extension registered for folders and directories.
- Native AppKit, Foundation, Uniform Type Identifiers, and ImageIO code.
- No package-manager dependencies or vendored executables.

## Trust boundaries

Finder provides the selected directory URL to the Quick Look extension. The
extension obtains security-scoped, read-only access while its preview panel is
alive and releases that access from `deinit`.

Names, metadata, text bytes, image bytes, and Markdown are untrusted input. The
UI displays them but must not treat them as commands, URLs to follow, or paths
to open.

## Enforced capabilities

The host entitlement file contains only:

- `com.apple.security.app-sandbox`

The preview extension adds only:

- `com.apple.security.files.user-selected.read-only`

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

| Resource | Limit |
| --- | ---: |
| Text bytes | 256 KB |
| Image file | 64 MB |
| Decoded image edge | 2,048 px |
| Syntax-highlighted characters | 200,000 |
| Markdown-rendered characters | 200,000 |

## Inert rendering

`CodeHighlighter` and `MarkdownRenderer` are forward-only scanners over the
already bounded string. They do not execute code, use a web view, launch an
application, or resolve a reference found in the file.

Rendered Markdown never emits a `.link` attribute or an
`NSTextAttachment`. Link destinations stay visible text and image references
stay placeholders. HTML is not interpreted.

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

- ImageIO and macOS filesystem metadata parsing remain native parser surfaces.
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
