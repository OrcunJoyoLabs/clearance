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
    let addedAt: Date         // When the folder was registered
    var id: String { path }
}
```

Stored separately from `RecentFilesStore`. The watched folder store only tracks *which directories* are watched — it does not store the scan results. Scan results are computed on demand.

### No changes to `RecentFilesStore`

Files that the user explicitly opens continue to be tracked in `RecentFilesStore` as before. Manually opened files persist in recent history regardless of their modification date.

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

Hidden directories are already skipped via `.skipsHiddenFiles`.

### Early date filter

Check `contentModificationDateKey` on each file during enumeration. Discard files older than 7 days immediately — do not collect them. This keeps memory usage constant regardless of codebase size.

### No depth limit

Claude can create markdown files anywhere in a project tree (e.g., `docs/superpowers/specs/`), so full recursive traversal is required. Only the junk directories above are pruned.

### Sort order

Results sorted by modification date (newest first), then alphabetically for ties.

## Sidebar Integration

### Where it appears

In the existing "Group by Folder" sidebar view (`entriesGroupedByFolder` in `RecentFilesSidebar`).

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

### Non-watched folder groups

Entries in `RecentFilesStore` that are *not* under any watched folder continue to appear grouped by their project root (existing behavior). The "Other" section also remains unchanged.

## User Flow

### Opening a folder

1. User selects a directory via Open panel (or drag-and-drop)
2. Directory is registered in `WatchedFolderStore`
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

- `WatchedFolderStore` persists across app launches (UserDefaults)
- On app launch, watched folders are restored but **not automatically scanned** — the user triggers refresh manually
- `RecentFilesStore` continues to persist independently

## What Gets Removed

The following one-shot folder import code is replaced:

- `queueOrImportFolder(at:)` in `WorkspaceViewModel`
- `importFolderURLs(_:)` in `WorkspaceViewModel`
- `PendingFolderImport` model and the confirmation dialog
- `folderImportConfirmationThreshold` constant
- The confirmation alert in `WorkspaceView`

The existing `folderImportURLs(in:)` static method is evolved into the new scan function with the 7-day filter and junk-directory skipping.

## Constants

- **Recency window**: 7 days (fixed, not configurable)
- **Junk directory skip list**: static set, not configurable
- **Supported extensions**: `.md`, `.markdown`, `.txt` (unchanged from current)

## Testing

- `WatchedFolderStore`: add/remove/persist/restore
- Scan function: finds recent files, skips old files, skips junk directories, handles empty directories
- Sidebar merging: scan-only files, manually-opened files, deduplication, non-watched groups unaffected
- Refresh: re-scan updates the section correctly
- Removing a watched folder: section disappears, manually-opened files remain in history
