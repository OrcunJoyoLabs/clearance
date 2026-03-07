# Clearance Changelog

## 1.1.0 - March 7, 2026

- Added bundled Graphviz DOT rendering for fenced `dot` and `graphviz` blocks, and now scale diagrams and markdown images to fit the reading column instead of sliding under the outline.
- Improved markdown rendering for structured guidance docs by treating embedded HTML/XML-like tags as literal text and correctly rendering fenced code blocks inside custom wrapper tags like `<Good>` and `<Bad>`.
- Tightened remote document loading so only explicit `http://` and `https://` URLs open remotely, while remote fetches now reject HTML and other unsupported content types instead of rendering them as markdown.
- Refined the address bar to behave more like a document field, including full-path editing for local files, safer URL parsing, and standard reopen behavior that reuses the existing window instead of opening duplicates.
- Local files now auto-refresh when they change on disk in View mode, while Edit mode still protects in-progress work by prompting before replacing unsaved content.

## 1.0.4 - March 6, 2026

- Added rendered document text zoom controls with standard macOS `Actual Size`, `Zoom In`, and `Zoom Out` menu commands, while preserving scroll position as the rendered view resizes.
- Refined rendered markdown typography and styling for a cleaner reading experience across built-in themes.
- Added bundled in-app release notes, which now open automatically on first launch after an update and remain available later from the app menu.
- Improved the recent history sidebar so entries can be removed directly and sidebar animations respect the system `Reduce Motion` setting.

## 1.0.3 - March 6, 2026

- Added secure remote markdown opening, rendering, navigation, and history handling alongside local documents.
- Introduced a smarter address bar that shows concise filenames or URLs in display mode, expands to full paths or URLs while editing, and now stays visible without pushing critical toolbar controls off-screen.
- Updated the outline sidebar to collapse and expand with native split-view behavior, including smoother animation in both the main workspace and pop-out windows.

## 1.0.2 - March 5, 2026

- Fixed internal markdown heading links so in-document anchor navigation reliably scrolls to the target heading.
- Switched markdown rendering to GFM-compatible parsing for tables, task lists, and strikethrough support.
- Added richer markdown rendering coverage and demo corpus validation for tables, math/LaTeX, and Mermaid content.
- Fixed task list layout so checkboxes render without duplicate bullet markers and with correct spacing/alignment.
