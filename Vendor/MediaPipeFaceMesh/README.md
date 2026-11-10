# MediaPipe Face Mesh native integration

This folder contains the native MediaPipe Face Mesh pipeline used by
FreeStage's Face Puppet source.

## Contents

- `src/` — C/C++ wrapper around TensorFlow Lite that exposes:
  - face detection
  - 478-point 3D face mesh (with iris)
  - head-pose / metric geometry estimation
  - 52 ARKit-style blendshape coefficients
- `TensorFlowLiteC.xcframework` — bundled TensorFlow Lite C runtime for
  macOS (arm64 + x86_64).
- `models/` — TensorFlow Lite model files:
  - `face_detection_short_range.tflite`
  - `face_landmark_with_attention.tflite`
  - `face_blendshapes.tflite`
- `LICENSE-cornpip` — BSD-3-Clause license for the wrapper code.
- `LICENSE-APACHE-2.0.txt` — Apache-2.0 license for the models and TFLite runtime.
- `THIRD_PARTY_NOTICES.md` — attribution notices from the upstream package.

## Source

The C/C++ wrapper originates from the Flutter package
[`mediapipe_face_mesh`](https://github.com/cornpip/mediapipe_face_mesh) by
cornpip. The macOS-specific native pieces (the C API and the bundled
`TensorFlowLiteC.xcframework`) were extracted from that package and wired
into FreeStage via a Swift bridging header.

## Swift interface

`Sources/FreeStage/Services/FaceMeshTracker.swift` creates the detector,
mesh, geometry, and blendshapes contexts and feeds `CVPixelBuffer`s to
them on a background queue. The renderer reads the latest `FaceMeshFrame`
and uses the landmarks / pose / blendshapes to draw the puppet.
