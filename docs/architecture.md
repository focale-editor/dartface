# Architecture

Dartface keeps image ownership, face-domain types, and detection mechanics separate so each layer can be tested without Flutter widgets or native libraries.

## Processing pipeline

1. `FaceDetector` accepts encoded bytes, an `imcodec.Image`, or an immutable `FaceImage`.
2. Imcodec decodes compressed files to straight-alpha RGBA. Raw camera input is normalized by `FaceImage`.
3. `AnalysisImage` downsamples to a bounded working resolution and derives its luminance plane. Accurate mode can also build two directly sampled, ±15-degree working images to recover tilted faces.
4. `LbpCascadeDetector` builds a grayscale pyramid, calculates one summed-area plane per level, and evaluates the 19-stage LBP cascade at each position.
5. Neighboring positive windows are grouped and duplicate boxes are suppressed.
6. The classical feature locator estimates eyes, nose, mouth points, and roll inside each accepted box, then rejects boxes whose aggregate landmark confidence is too low.
7. Rotated-pass coordinates are restored to the source orientation and merged with the primary detections. These secondary scans use a 640-pixel bound and the balanced cascade density to contain their cost while the primary accurate scan keeps its full 720-pixel detail.
8. Source-pixel coordinates are returned as immutable `DetectedFace` values.

On native platforms, asynchronous entry points transfer the owned pixel buffer and put decoding plus the complete pipeline in `Isolate.run`. Only plain values are captured by the worker closure, because reaching through the caller's `FaceImage` would make the isolate copy the pixel buffer next to the transfer that already moves it. Web calls execute inline. Synchronous entry points are available to callers that already manage their own worker isolate.

## Deferred work

An image that contains no face never needs anything but luminance, and the skin and red-chroma statistics exist only for the opt-in heuristic detector. `AnalysisImage` therefore keeps the sampled working pixels and builds every other plane, including all four summed-area planes, on first use. Pyramid levels are mapped back to working coordinates with the scale each level actually received, because rounding a resized level moves it slightly away from the requested scale.

## Landmark geometry

The cascade and the heuristic scanner frame a face differently, so each carries
its own landmark geometry: where the eyes and mouth are expected to sit inside a
window, and how far a search may wander from there. The cascade's values were
measured from hand-labelled landmarks on the reference corpus rather than
assumed, because the cascade frames a face higher and wider than an idealized
crop would suggest.

Two properties of the search matter more than the response function itself. The
distance to the expected position is weighted heavily, because the darkest spot
in an eye band is often an eyebrow or a shadow. And the mouth is searched in a
narrow band under the midpoint of the two located eyes, over a patch about as
wide as a mouth, which finds the lip line instead of the corner shadows that are
darker but off-center. `test/corpus/measure_landmarks.dart` reports the
resulting error against the labelled corpus.

## Source layout

- `lib/src/detector`: the public detector service, cascade evaluation, landmark estimation, overlap suppression, and generated model parameters.
- `lib/src/image`: immutable input normalization and working-image planes.
- `lib/src/model`: immutable public result values and options.
- `lib/src/exceptions`: typed package failures.

There is no presentation layer because Dartface is a reusable detection package and does not own application state or widgets.

## Model representation

`tool/generate_lbp_cascade.dart` converts the licensed OpenCV XML model into typed Dart constants. Runtime code does not parse files, load assets, or invoke OpenCV. The generated values remain reviewable and deterministic; the exact upstream revision is recorded in `THIRD_PARTY_NOTICES.md`.

## Coordinate conventions

The origin is the source image's top-left corner. Horizontal coordinates increase rightward and vertical coordinates increase downward. Bounding boxes use half-open right and bottom edges internally. `rollDegrees` is positive clockwise in image space.

Landmark names refer to the side visible in the image, not the subject's anatomical left or right.
