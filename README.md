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

### Presenter rundown model

```
PresenterRundown
 ├── Segments (ordered cues)
 │    ├── Camera angle / chroma key / camera framing
 │    ├── Placeholder reference (shared, named source slot)
 │    └── Cue Layers (this cue only — screen share, image, video, NDI, Syphon, colour)
 └── Global Layers (every cue — logo bug, backdrop, lower third)
```

A cue layer's **Placement** decides where it composites: `Background` sits behind
the cue content (after the global background layers), `Foreground` sits above the
cue content but beneath global foreground layers. Cue layers reach preview, live,
recording, and streaming automatically because every surface renders the same
`Scene` produced by `ShowStore.scene(for:)`.

## Status

Early scaffold. The current target is a compilable SwiftUI app shell with the data model in place, so the architecture can grow incrementally.

## Show library

FreeStage keeps everything it reads and writes inside one **show library** folder. On first launch a setup sheet asks where that folder should live (default `~/Movies/FreeStage`), and the folder template is created there:

```
<library root>/
├── FreeStage Library.md      Marker + description of the layout
├── GlobalAssets/             Shared assets, available to every show
│   ├── LUTs/                 Colour lookup tables (.cube)
│   ├── Plugins/              Third-party effect bundles and handlers
│   ├── Sound Effects/        Stings, applause, rimshots
│   ├── Music/                Walk-on, walk-off and backing beds
│   ├── Memes/                Reaction images and clips
│   ├── Logos/                Pre-keyed logos for bugs and lower thirds
│   ├── Images/               Stills, backdrops and backgrounds
│   ├── Videos/               Clips, loops and VT rolls
│   └── Templates/            Imported show styles and template packs
├── Shows/                    Saved show packages (.fst)
└── Output/
    ├── Recordings/           Recordings from ⇧⌘R or GO
    └── Exports/              Manual exports and renders
```

The template is written by `ShowLibrary.prepare()` (`Sources/FreeStage/Services/ShowLibrary.swift`), which is deliberately **additive and idempotent** — it never deletes or overwrites anything, so it is safe to run on every launch:

- Missing folders are recreated; a stray file squatting on a folder name is reported instead of deleted.
- A `README.md` is written into each folder only if one is not already there.
- Each folder drops an empty directory, never a placeholder file, so Finder shows the structure immediately.

Where things live:

| Concern | Setting | Default |
| --- | --- | --- |
| Library root | Settings → Show Library → Choose… (also on the Project Manager) | `~/Movies/FreeStage` |
| Recordings | Settings → Recording → Choose… (override) | `<library root>/Output/Recordings` |
| Shows | File → Save (⌘S) / Save As… (⇧⌘S) | `<library root>/Shows` (suggested) |

Changing the library root creates the template at the new location, and recordings that pointed inside the old library follow it automatically. A custom recording directory outside the library is preserved, and "Use Library Default" returns to `Output/Recordings`.

## Saving shows

`ShowDocumentSaver` (`Sources/FreeStage/Services/ShowDocumentSaver.swift`) is the only thing that writes show packages, so a manual save and an autosave can never overlap or leave a half-written document.

| Action | Shortcut | Behaviour |
| --- | --- | --- |
| Save | ⌘S | Overwrites the open package. If the show has never been saved, it opens the Save panel first. |
| Save As… | ⇧⌘S | Always asks for a new location and adopts it as the current document. |
| Autosave | — | Every 3 minutes, writes the open package only when its content actually changed. Never prompts, and never creates a package for a show that has not been saved yet. |

Dirty tracking uses `Show.contentHash`, which hashes the document while ignoring the `workspace` block. Moving the cue playhead, changing the selection or toggling a panel therefore never triggers a disk write; changing a cue, layer, or asset does.

Saved packages are written with **deterministic asset names** derived from the source path (`clip-1f4a9c22.mov`), so repeated autosaves refresh the copy in the package instead of piling up `clip-1`, `clip-2`, … duplicates. Assets referenced by per-cue layers — and their chroma-key backgrounds — are packaged along with scene layers and global layers.

## Stable Debug signing (optional)

By default FreeStage Debug builds are **ad-hoc signed** (`CODE_SIGN_IDENTITY = -`). That works, but every Xcode rebuild produces a new binary signature (cdhash). macOS stores Screen Recording / Camera / Microphone TCC grants against the app's signature, so the permission can stop working after a rebuild even though System Settings still shows FreeStage as enabled.

To keep the grant stable across rebuilds, run the self-signed Debug identity setup once per machine:

```bash
./scripts/setup-debug-signing.sh
```

The script:
1. Creates a self-signed certificate named **FreeStage Debug** in `~/.freestage/`.
2. Imports it into your **login** keychain (you may be prompted for your keychain password).
3. Writes the certificate's SHA-1 hash to `Resources/DebugCodeSigningLocal.xcconfig` (gitignored).

The Debug build then uses that hash as its code signing identity. The grant only needs to be approved once; subsequent rebuilds reuse the same signature.

To revert to ad-hoc Debug builds, delete `Resources/DebugCodeSigningLocal.xcconfig` or run `xcodegen generate` again.

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
