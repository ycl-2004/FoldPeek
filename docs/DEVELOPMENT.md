# Development notes

## Scope

This edition has one responsibility: browse a folder's contents, read-only and bounded, from a Quick Look panel. That covers listing a directory, expanding a subfolder in place, and showing a capped plain-text or image preview of one selected file.

Features that require archive parsing, external tools, background execution, network access, active-content rendering, cross-container preferences, or external file launching are intentionally out of scope.

## Project layout

```text
FoldPeekApp/
  WelcomeView.swift                      Static setup-only host UI
  FoldPeekApp.swift                      Host entry point
  FoldPeekApp.entitlements               App Sandbox only
FoldPeekPreviewExtension/
  FoldPeekPreviewController.swift        Quick Look entry point, index pane, search
  FolderNode.swift                       Lazy tree node, item budget, in-memory filter
  PreviewPaneView.swift                  Content pane: title, preview card, metadata
  PaperTheme.swift                       Colour and type tokens for the paper design
  PaperViews.swift                       Card grain, diamond divider, index rows, badge
  CodeHighlighter.swift                  Language table and single-pass token scanner
  CodeTextView.swift                     Indent guides and the line-number gutter
  MarkdownRenderer.swift                 Markdown block/inline scanner and typography
  MetadataGridView.swift                 The inspector's two-column fact ledger
  FoldPeekPreviewExtension.entitlements  Sandboxed read-only access
  Info.plist                             Folder/directory UTTypes only
Shared/
  IndexedEntry.swift                     Minimal metadata model
  DirectoryScanner.swift                 Bounded single-level enumeration
  FilePreviewLoader.swift                Bounded text/image reading and type gating
```

The Xcode project has no shell-script build phases and no Swift Package dependencies.

## Security invariants

- Keep both targets sandboxed.
- Do not add network, automation, accessibility, Apple Events, executable-file, or broad-folder entitlements.
- Keep the extension read-only.
- Do not execute external programs or download runtime dependencies.
- Do not register login items, LaunchAgents, URL schemes, or persistent helpers.
- Keep every directory read single-level; recursion happens only through explicit user expansion, and only within the depth and budget caps.
- Do not follow symbolic links, in the tree or in the preview pane.
- Hold security-scoped access exactly as long as the panel lives, and release it in `deinit`.
- Render only inert content. Text goes to a plain-text `NSTextView` with rich text, graphics import, and data detectors off. Images go through ImageIO with a pixel-size cap. Adding any other renderer means adding a parser, so treat it as a new threat model.
- Never read a file whole. Every read is capped before it reaches memory.
- Preview only regular files, so directories, FIFOs, sockets, and device nodes are refused.
- Keep the filter in memory. It may narrow and expand nodes that are already
  loaded, but it must never read a directory to answer a query; otherwise a
  keystroke could walk the whole tree and defeat the budgets.
- Keep the palette fixed. `PaperTheme` is a design, not a set of semantic
  system colours, and the two must not be mixed within one surface. Its values
  track the YC brand tokens; colour carries a role, not a decoration — wine is
  identity and judgement, denim is structure and anything technical, ink is
  body. Never use wine to signal an error.
- Draw block decorations, do not colour them. A `.backgroundColor` attribute
  paints per glyph run and leaves a ragged edge on short lines, so fenced code
  panels, table rules, and quote bars are drawn by `CodeTextView` from range
  attributes.
- Expand a marked span to its longest effective range before drawing it. AppKit
  redraws in horizontal bands and visits a tall span once per band with a
  clipped range; drawing those directly produces one shape per band instead of
  one per span.
- Prose and source get opposite treatments. Source keeps the gutter, indent
  guides, and the ruled grain; prose drops all three and is held to
  `PaperTheme.readingWidth`.
- Keep the highlighter and the Markdown renderer scanners. They may classify
  characters we already hold and style them; they must never hand the file to a
  document engine — including `NSAttributedString(markdown:)` — resolve
  anything they find, or use regular expressions, whose backtracking a hostile
  file could drive.
- Never emit a `.link` attribute or an `NSTextAttachment`. A rendered link must
  stay inert text, and an image reference must stay a placeholder; loading
  either would mean following a path the file chose.

If a future feature conflicts with one of these invariants, document the threat model and create a separate target or fork instead of expanding this extension.

## Bounds

All limits live next to the code that enforces them:

- `DirectoryScanner.maximumItemCount` — 2,000 entries per directory
- `FolderTreeBudget.maximumTotalItems` — 20,000 entries per panel
- `FolderNode.maximumDepth` — 8 expansion levels
- `FilePreviewLoader.maximumTextBytes` — 256 KB of text
- `FilePreviewLoader.maximumImageFileBytes` — 64 MB image file
- `FilePreviewLoader.maximumImagePixelSize` — 2,048 px decoded
- `CodeHighlighter.maximumHighlightCharacters` — 200,000 characters coloured
- `MarkdownRenderer.maximumRenderCharacters` — 200,000 characters laid out

## Verification

Static checks should confirm:

- Only `public.folder` and `public.directory` are registered.
- The host has only `com.apple.security.app-sandbox`.
- The extension additionally has only `com.apple.security.files.user-selected.read-only`.
- No network, subprocess, persistence, or executable-script APIs are present.
- `NSAttributedString(url:)`, `WKWebView`, and any HTML/RTF/Markdown rendering path stay absent.

Signed builds should be checked too. Ad-hoc signing injects `com.apple.security.get-task-allow`; re-sign with the repository entitlements before treating a build as final, and confirm with `codesign -d --entitlements -`.

Runtime verification, when explicitly requested, should confirm both processes show as sandboxed in Activity Monitor.
