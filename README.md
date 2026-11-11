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

## License

TBD.
