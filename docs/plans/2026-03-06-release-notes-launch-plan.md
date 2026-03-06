# Release Notes Launch Plan

**Goal:** Open the bundled release notes markdown document automatically on the first launch after an app update, and provide a menu command to reopen it later.

**Decision:** Use the existing repo-root `CHANGELOG.md` as the single release-notes source of truth and bundle it with the app. Reuse the current document open notification path so release notes open like any other markdown document.

## Steps

1. Add tests for release-notes version tracking so first install does not show notes, relaunching the same version does not show notes, and launching a newer version does.
2. Add tests for release-notes bundle lookup using a temporary bundle fixture with a markdown resource and app version in `Info.plist`.
3. Extend app settings with persisted release-notes version tracking.
4. Add a small release-notes helper for bundle resource and current-version lookup.
5. Bundle `CHANGELOG.md`, auto-open it once after an update, and add a `Show Release Notes` menu command.
6. Run focused tests, regenerate the Xcode project if needed, and commit the change.
