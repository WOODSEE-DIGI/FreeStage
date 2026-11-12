# FreeStage

A native macOS live production switcher and show sequencer.

FreeStage is designed as an OBS alternative with a focus on clarity, direct manipulation, and a QLab/CueCam-style show workflow. You build a show as an ordered list of cues — each cue fires a scene — and progress through the show while recording or streaming.

## Product split

- **DualCast** — slimline NDI screen-capture relay for multiple displays.
- **FreeStage** — production canvas that consumes DualCast's NDI feeds (alongside cameras, media, browser sources, and overlays) and outputs to virtual camera, NDI, Syphon, recording, and streaming.

## Core concepts

```
Show
 └── Cues (ordered, fireable)
      └── Scene
           └── Layers (ordered back-to-front)
                 ├── Source (camera, NDI, media, screen, browser, color, text, image, video)
                 ├── Transform (position, scale, rotation, crop)
                 ├── Filters (chroma key with independent background transform, AI keyer, color correction)
                 └── Blend Mode
```

## Status

Early scaffold. The current target is a compilable SwiftUI app shell with the data model in place, so the architecture can grow incrementally.

## Build

This project is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml` or adding files:

```bash
xcodegen generate
xcodebuild -project FreeStage.xcodeproj -scheme FreeStage -configuration Debug -destination 'platform=macOS' build
```

## Package a DMG

```bash
scripts/build-dmg.sh
```

The script regenerates the project, builds the Release configuration into
`build/DerivedData`, re-signs the app (ad-hoc by default) so the bundle is
sealed and carries the entitlements from `Resources/FreeStage.entitlements`,
then writes a drag-to-install `build/FreeStage-<version>.dmg` containing
`FreeStage.app` and an `Applications` symlink. It prints the version, size and
SHA-256 of the result.

Overridable environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONFIGURATION` | `Release` | Build configuration |
| `DIST_DIR` | `./build` | Where the DMG is written |
| `DERIVED_DATA_DIR` | `./build/DerivedData` | Derived data location |
| `SIGN_IDENTITY` | `-` (ad-hoc) | Codesign identity; a Developer ID keeps restricted entitlements |

The build is not notarised, so the first launch on another Mac needs the usual
Gatekeeper override:

```bash
xattr -dr com.apple.quarantine /Applications/FreeStage.app
```

## License

TBD.
