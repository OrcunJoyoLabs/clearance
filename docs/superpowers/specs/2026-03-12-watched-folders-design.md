# Watched Folders

## Problem

When working in a project directory, Claude (and other tools) create markdown files throughout the codebase. Opening and tracking these files individually in Clearance is tedious. Users need a way to point at a project folder and automatically see recently-modified markdown files without manual file-by-file importing.

## Solution

Replace the current one-shot folder import with **watched folders**. When a user opens a directory, Clearance registers it as a watched folder. In the "Group by Folder" sidebar view, watched folders display markdown files modified in the last 7 days, with a manual refresh button to re-scan on demand.

## Data Model

### New: `WatchedFolderStore`

Persisted in UserDefaults as JSON. Manages the list of watched directory paths.

```swift
struct WatchedFolderEntry: Codable, Identifiable {
    let path: String          // Absolute path to watched directory
    let bookmarkData: Data    // Security-scoped bookmark for persistent access
    let addedAt: Date         // When the folder was registered
    var id: String { path }
}
```

**Security-scoped bookmarks**: When a folder is selected via `NSOpenPanel`, persist a security-scoped bookmark (`URL.bookmarkData(options: .withSecurityScope)`). On restore, resolve the bookmark and call `url.startAccessingSecurityScopedResource()` before scanning. Call `url.stopAccessingSecurityScopedResource()` when done. This ensures access survives app restarts.

Stored separately from `RecentFilesStore`. The watched folder store only tracks *which directories* are watched — it does not store the scan results. Scan results are computed on demand.

### Sidebar item type

Introduce a `SidebarItem` enum to represent both manually-opened and scan-discovered files:

```swift
enum SidebarItem: Identifiable {
    case recentEntry(RecentFileEntry)
    case scannedFile(url: URL, modificationDate: Date)

    var id: String { /* path-based */ }
    var displayName: String { /* filename */ }
    var path: String { /* full path */ }
    var sortDate: Date { /* lastOpenedAt or modificationDate */ }
}
```

This allows the sidebar to distinguish the two sources and display them appropriately.

### No changes to `RecentFilesStore`

Files that the user explicitly opens continue to be tracked in `RecentFilesStore` as before. Manually opened files persist in recent history regardless of their modification date.

The `add(urls:)` bulk import method on `RecentFilesStore` becomes dead code with the removal of the one-shot import flow and should be removed.

## Directory Scanning

### Scan function

Recursively enumerate the watched directory looking for `.md`, `.markdown`, and `.txt` files modified within the last 7 days.

### Performance: skip known junk directories

When the enumerator encounters any of these directory names, call `skipDescendants()`:

- `node_modules`
- `build`
- `dist`
- `.build`
- `DerivedData`
- `Pods`
- `vendor`
- `.venv`
- `__pycache__`
- `target`
- `.gradle`
- `.next`
- `.nuxt`

Hidden directories are already skipped via `.skipsHiddenFiles`. This means directories like `.github` are also skipped — this is an accepted limitation.

### Early date filter

Check `contentModificationDateKey` on each file during enumeration. Discard files older than 7 days immediately — do not collect them. This keeps memory usage constant regardless of codebase size.

### No depth limit

Claude can create markdown files anywhere in a project tree (e.g., `docs/superpowers/specs/`), so full recursive traversal is required. Only the junk directories above are pruned.

### Sort order

Results sorted by modification date (newest first), then alphabetically for ties.

### Unavailable directories

If a watched directory no longer exists on disk (deleted, renamed, external drive unmounted), skip the scan. Show the section header dimmed with no files listed. The "Stop Watching Folder" context menu remains available for cleanup.

## Sidebar Integration

### Where it appears

In the existing "Group by Folder" sidebar view (`entriesGroupedByFolder` in `RecentFilesSidebar`).

### Watched folders take priority over ProjectRootResolver

When building the folder-grouped sidebar, watched folders are processed first. Any `RecentFileEntry` whose path falls under a watched folder directory is **claimed** by that watched folder's section and excluded from the `ProjectRootResolver`-based grouping. This prevents files from appearing in two sections.

When a file falls under multiple watched folders (e.g., `/projects` and `/projects/myapp`), it is assigned to the **deepest** (most-specific) matching watched folder.

### Section composition

For each watched folder, the section displays the **union** of:

1. **Scanned files** — markdown files in the directory modified in last 7 days (from the scan)
2. **Manually opened files** — entries from `RecentFilesStore` whose paths fall under the watched directory

Deduplicated by path. If a file appears in both sets, the manually-opened entry takes priority (it persists even after the file ages past 7 days).

### Section header

Each watched folder section shows:
- **Title**: directory display name (last path component)
- **Subtitle**: full directory path
- **Refresh button**: `arrow.clockwise` icon — triggers re-scan of that specific directory

### File rows

- Files that were manually opened show the same row style as today
- Files discovered only by scan (not yet opened) use the file's **modification date** as the displayed date, since there is no "last opened" date

### Group by Date view

Scan-only files (never opened) do **not** appear in the "Group by Date" sidebar view. They have no `lastOpenedAt` and were never explicitly opened. Only files tracked in `RecentFilesStore` appear in date-grouped mode.

### Non-watched folder groups

Entries in `RecentFilesStore` that are *not* under any watched folder continue to appear grouped by their project root (existing behavior). The "Other" section also remains unchanged.

## User Flow

### Opening a folder

1. User selects a directory via Open panel (or drag-and-drop)
2. Security-scoped bookmark is created and directory is registered in `WatchedFolderStore`
3. Initial scan runs immediately
4. The most recently modified file from the scan is opened
5. Sidebar (in folder-grouped mode) shows the watched folder section with scanned files

### Refreshing

1. User clicks the refresh button on a watched folder's section header
2. Re-scan runs for that directory only
3. Section updates with the latest results merged with manually-opened files

### Opening a discovered file

1. User clicks a file in a watched folder section
2. File opens in the main view
3. File is added to `RecentFilesStore` — it now persists even if it ages past 7 days

### Removing a watched folder

Context menu on the section header provides "Stop Watching Folder" action. This removes the directory from `WatchedFolderStore`. Files that were manually opened from that folder remain in `RecentFilesStore`.

## Persistence

- `WatchedFolderStore` persists across app launches (UserDefaults, with security-scoped bookmarks)
- On app launch, watched folders are restored and **automatically scanned** — the scan is fast with the 7-day filter and junk-directory pruning
- `RecentFilesStore` continues to persist independently

## What Gets Removed

The following one-shot folder import code is replaced:

- `queueOrImportFolder(at:)` in `WorkspaceViewModel`
- `importFolderURLs(_:)` in `WorkspaceViewModel`
- `PendingFolderImport` model and the confirmation dialog
- `folderImportConfirmationThreshold` constant
- The confirmation alert in `WorkspaceView`
- `add(urls:)` on `RecentFilesStore` (dead code after removal of bulk import)

The existing `folderImportURLs(in:)` static method is evolved into the new scan function with the 7-day filter and junk-directory skipping.

## Constants

- **Recency window**: 7 days (fixed, not configurable)
- **Junk directory skip list**: static set, not configurable
- **Supported extensions**: `.md`, `.markdown`, `.txt` (unchanged from current)

## Testing

- `WatchedFolderStore`: add/remove/persist/restore, security-scoped bookmark round-trip
- Scan function: finds recent files, skips old files, skips junk directories, handles empty directories, handles missing directories
- Sidebar merging: scan-only files, manually-opened files, deduplication, watched folder priority over ProjectRootResolver, deepest-match for overlapping watches, non-watched groups unaffected
- Sidebar item type: correct display for both scanned and manually-opened files
- Group by Date: scan-only files excluded
- Refresh: re-scan updates the section correctly
- Removing a watched folder: section disappears, manually-opened files remain in history
