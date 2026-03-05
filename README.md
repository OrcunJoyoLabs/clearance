# Clearance

Clearance is a native macOS Markdown workspace focused on YAML-frontmatter Markdown files.

## Current V1 Capabilities

- Open `.md` / Markdown files from the app.
- Sidebar of recently opened files (file name + full path), newest first.
- View mode:
  - Beautiful rendered Markdown document.
  - Frontmatter rendered as a full metadata table.
- Edit mode:
  - Syntax-highlighted Markdown editing via embedded CodeMirror.
  - Deep undo history (`undoDepth: 10000`).
- Autosave with debounced writes while editing.
- Default open mode setting (`View` or `Edit`).
- Pop-out document windows from the workspace.
- `.md` file association declared in app `Info.plist`.

## Build and Run

1. Generate the Xcode project:

```bash
xcodegen generate
```

2. Build:

```bash
xcodebuild -project Clearance.xcodeproj -scheme Clearance -configuration Debug -destination 'platform=macOS' build
```

3. Test:

```bash
xcodebuild test -project Clearance.xcodeproj -scheme Clearance -destination 'platform=macOS'
```

4. Open in Xcode and run `Clearance`.

## Auto Releases + Sparkle Updates

Tag pushes (`v*`) run `.github/workflows/release.yml` to:

- Build a Release app.
- Codesign with Developer ID Application cert.
- Notarize and staple.
- Package `Clearance-<version>-macOS.zip`.
- Generate and sign `appcast.xml` with Sparkle EdDSA keys.
- Publish both files to the GitHub Release.

The app uses:

- `SUFeedURL = $(SPARKLE_FEED_URL)` (set to `https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml` in CI builds).
- `SUPublicEDKey = $(SPARKLE_PUBLIC_ED_KEY)`.

If either value is missing, `Check for Updates…` is disabled at runtime.

### Required GitHub Secrets

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`: base64-encoded `.p12` certificate.
- `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`: password for the `.p12`.
- `DEVELOPER_ID_APPLICATION_SIGNING_IDENTITY`: full codesign identity string.
- `APPLE_ID`: Apple ID email for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `SPARKLE_PUBLIC_ED_KEY`: Sparkle public key.
- `SPARKLE_PRIVATE_ED_KEY`: Sparkle private key.

### Releasing

1. Make sure all required secrets are configured.
2. Create a version tag:

```bash
git tag v1.0.1
git push origin v1.0.1
```

3. Wait for the `Build and Release` workflow to finish.

## Asset Regeneration

Regenerate the app icon assets from the in-repo source SVG:

```bash
scripts/generate-app-iconset.sh
```

## Notes

- CodeMirror assets are vendored under `Clearance/Resources/vendor/codemirror` and loaded locally.
- Autosave is currently debounce-based and writes directly to the source file.
- External file-change conflict handling is not yet implemented.
