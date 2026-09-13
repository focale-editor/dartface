<p align="center">
  <img src="screenshots/overview.png" alt="Dartface package illustration" width="180">
</p>

# Dartface

Dartface detects mostly frontal faces in still photographs with a pure Dart detection engine for Flutter. It returns source-pixel bounding boxes, six estimated landmarks, confidence scores, and in-plane rotation without TensorFlow Lite, FFI or platform channels.

The default detector evaluates a trained local-binary-pattern cascade and groups neighboring positive windows. Encoded files are decoded by the Focale [`imcodec`](https://pub.dev/packages/imcodec) package. No image or face data leaves the device.

> [!NOTE]
> Dartface focuses on still-image face detection for photo editing. It does not identify people and does not provide recognition, embeddings, a dense face mesh, expression classification, tracking, liveness checks, or segmentation.

## Features

- Pure Dart multi-scale LBP cascade evaluation.
- JPEG, PNG, WebP, GIF, BMP, TIFF, TGA, QOI, and JPEG XL input through Imcodec.
- Direct `imcodec.Image`, grayscale, RGB, BGR, RGBA, BGRA, ARGB, ABGR, and planar YUV420 input.
- Background-isolate decoding and detection on native Dart and Flutter platforms.
- Inline execution on the web, where isolates are unavailable.
- Immutable results and owned image buffers.
- Configurable accuracy, face-size bounds, box and landmark confidence thresholds, result limit, and decoded-pixel safety limit.
- Six lightweight landmark estimates: both eyes, nose tip, and three mouth points.
- Optional accurate-mode recovery for faces tilted about 15 degrees in either direction.

## Installation

Add Dartface to a Flutter package:

```sh
flutter pub add dartface
```

## Detect an encoded image

```dart
import 'dart:typed_data';

import 'package:dartface/dartface.dart';

Future<List<DetectedFace>> findFaces(Uint8List jpegBytes) async {
  final FaceDetector detector = await FaceDetector.create(
    options: const FaceDetectorOptions(
      accuracy: FaceDetectionAccuracy.balanced,
      minimumFaceSize: 0.15,
      confidenceThreshold: 0.58,
    ),
  );
  try {
    return await detector.detectFacesFromBytes(jpegBytes);
  } finally {
    await detector.dispose();
  }
}
```

Each result uses the source image's pixel coordinate system:

```dart
for (final DetectedFace face in faces) {
  print(
    '${face.boundingBox}: box=${face.confidence}, '
    'landmarks=${face.landmarkConfidence}',
  );
  print(face.landmark(FaceLandmarkType.leftEye)?.position);
}
```

Neither confidence value is a calibrated probability. `confidence` ranks support for the face box, while `landmarkConfidence` is the mean confidence of the six sparse feature positions. The default options require both to be usable. In accurate mode, the held-out portion of the small reference corpus has a mean landmark error of 7.3% of the eye spacing; mean roll error across all labelled accurate-mode faces is 1.5 degrees.

## Detect decoded pixels

Use `FaceImage` when pixels already come from an editor or another imaging pipeline:

```dart
final FaceImage frame = FaceImage.fromBytes(
  width: width,
  height: height,
  bytes: bgraBytes,
  pixelFormat: FacePixelFormat.bgra8888,
  rowStride: bytesPerRow,
);

final List<DetectedFace> faces = await detector.detectFacesAsync(frame);
```

Planar YUV420 input is also accepted for interoperability, although Dartface is not tuned for continuous video:

```dart
final FaceImage frame = FaceImage.fromYuv420(
  width: width,
  height: height,
  luminancePlane: yPlane,
  chromaBluePlane: uPlane,
  chromaRedPlane: vPlane,
  luminanceRowStride: yRowStride,
  chromaRowStride: uvRowStride,
  chromaPixelStride: uvPixelStride,
);
```

If the caller already has an `imcodec.Image`, `detectFacesFromImage` avoids an encode/decode cycle.

`FaceImage.rgbaBytes` returns a defensive copy. When pixels are only read, such as when handing a frame to another library, `FaceImage.rgbaView` returns an unmodifiable view over the same buffer instead.

## Options

| Option                      |    Default | Effect                                                             |
|-----------------------------|-----------:|--------------------------------------------------------------------|
| `accuracy`                  | `balanced` | Selects working resolution and scan density.                       |
| `minimumFaceSize`           |     `0.15` | Smallest face height as a fraction of the shortest image edge.     |
| `maximumFaceSize`           |     `0.95` | Largest face height as a fraction of the shortest image edge.      |
| `confidenceThreshold`       |     `0.58` | Drops detections below this score.                                 |
| `minimumLandmarkConfidence` |     `0.40` | Drops boxes whose six feature estimates are unreliable as a group. |
| `maximumFaces`              |       `10` | Limits returned faces after overlap suppression.                   |
| `runInIsolate`              |     `true` | Moves asynchronous native work off the UI isolate.                 |
| `maximumDecodedPixels`      | `40000000` | Rejects unexpectedly large encoded images.                         |
| `enableRotationRecovery`    |     `true` | Adds two ±15° recovery scans in `accurate` mode only.              |
| `enableHeuristicFallback`   |    `false` | Tries an experimental detector for drawings after a cascade miss.  |

`fast` uses the smallest working image and coarsest position steps. `accurate` retains more input detail, scans more densely, and by default runs two secondary deskew passes at a bounded 640-pixel resolution. A face cannot be evaluated below the cascade's 45-pixel working window, so use `accurate` for small, tilted, or group portraits. Disable `enableRotationRecovery` when all photographs are upright and lower latency matters.

The heuristic fallback is intentionally opt-in. It helps with synthetic portraits and illustrations but can mistake symmetric objects for faces.

## Detection limits

The bundled cascade is trained for mostly frontal human faces. Accurate mode recovers modest in-plane tilt, but strong profile views, occlusion, very small faces, blur, extreme rotation, and extreme illumination can still be missed. Dartface is designed for one-shot analysis of still photographs, not real-time video.

Do not use Dartface as the only control for identity, safety, access, or liveness. Evaluate it on representative data from every intended camera, demographic, pose, and lighting condition.

## Design and licensing

The package architecture and processing pipeline are documented in [`docs/architecture.md`](https://github.com/focale-editor/dartface/blob/main/docs/architecture.md).

The compact cascade parameters are generated from OpenCV's improved frontal-face LBP model. Their separate copyright, license, source revision, and research citation are recorded in [`THIRD_PARTY_NOTICES.md`](https://github.com/focale-editor/dartface/blob/main/THIRD_PARTY_NOTICES.md).

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
