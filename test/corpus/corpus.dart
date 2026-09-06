import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartface/dartface.dart';

/// Directory holding the encoded corpus images.
const String corpusDirectory = 'test/corpus/images';

/// An expected face, expressed in the source image's pixel coordinates.
final class ExpectedFace {
  /// Describes one face that the cascade is expected to find.
  const ExpectedFace({
    required this.centerX,
    required this.centerY,
    required this.size,
    this.landmarks,
    this.landmarksUsedForTuning = true,
  });

  /// Horizontal center of the reference box.
  final double centerX;

  /// Vertical center of the reference box.
  final double centerY;

  /// Side length of the reference box.
  final double size;

  /// Hand-labelled landmarks of this face, when they were measured.
  final ExpectedLandmarks? landmarks;

  /// Whether the landmark estimator was tuned with this annotation available.
  final bool landmarksUsedForTuning;

  /// Whether [face] covers the same region as this reference.
  ///
  /// The bounds stay wide because the cascade snaps boxes to its pyramid
  /// steps, so the same face moves by a few pixels between accuracy presets.
  bool matches(DetectedFace face) {
    final double toleranceX = size * 0.45;
    final double toleranceY = size * 0.45;
    return (face.boundingBox.center.x - centerX).abs() <= toleranceX &&
        (face.boundingBox.center.y - centerY).abs() <= toleranceY &&
        face.boundingBox.width >= size * 0.6 &&
        face.boundingBox.width <= size * 1.6;
  }

  @override
  String toString() => 'ExpectedFace(center: ($centerX, $centerY), size: $size)';
}

/// Hand-labelled landmark positions for one face.
///
/// The positions were read off a zoomed, grid-annotated crop of the source
/// photograph. They are accurate to roughly one source pixel, which is far
/// tighter than the accuracy the estimator is expected to reach.
final class ExpectedLandmarks {
  /// Describes the true landmark positions of one face.
  const ExpectedLandmarks({
    required this.leftEyeX,
    required this.leftEyeY,
    required this.rightEyeX,
    required this.rightEyeY,
    required this.mouthX,
    required this.mouthY,
  });

  /// Center of the eye shown on the left of the image.
  final double leftEyeX;

  /// Vertical center of the eye shown on the left of the image.
  final double leftEyeY;

  /// Center of the eye shown on the right of the image.
  final double rightEyeX;

  /// Vertical center of the eye shown on the right of the image.
  final double rightEyeY;

  /// Center of the mouth opening.
  final double mouthX;

  /// Vertical center of the mouth opening.
  final double mouthY;

  /// Distance between both eye centers, used to normalize errors.
  double get interocularDistance {
    final double horizontal = rightEyeX - leftEyeX;
    final double vertical = rightEyeY - leftEyeY;
    return math.sqrt(horizontal * horizontal + vertical * vertical);
  }

  /// True in-plane rotation implied by the eye line, positive clockwise.
  double get rollDegrees => math.atan2(rightEyeY - leftEyeY, rightEyeX - leftEyeX) * 180 / math.pi;

  /// Mean landmark distance of [face], as a fraction of [interocularDistance].
  ///
  /// This is the normalized mean error used by face-alignment benchmarks. A
  /// value of 0.10 means the average landmark sits a tenth of an eye spacing
  /// away from its true position.
  double normalizedMeanError(DetectedFace face) {
    final double left = _distance(face, FaceLandmarkType.leftEye, leftEyeX, leftEyeY);
    final double right = _distance(face, FaceLandmarkType.rightEye, rightEyeX, rightEyeY);
    final double mouth = _distance(face, FaceLandmarkType.mouthCenter, mouthX, mouthY);
    return (left + right + mouth) / 3 / interocularDistance;
  }

  /// Distance between an estimated landmark and its true position.
  double _distance(DetectedFace face, FaceLandmarkType type, double x, double y) {
    final FaceLandmark? landmark = face.landmark(type);
    if (landmark == null) {
      return double.infinity;
    }
    final double horizontal = landmark.position.x - x;
    final double vertical = landmark.position.y - y;
    return math.sqrt(horizontal * horizontal + vertical * vertical);
  }
}

/// One labelled corpus entry.
final class CorpusEntry {
  /// Describes an image and what the detector should report for it.
  const CorpusEntry({
    required this.fileName,
    required this.width,
    required this.height,
    required this.expectedFaces,
    this.minimumFaceSize = 0.15,
    this.accuracies = FaceDetectionAccuracy.values,
    this.note,
  });

  /// File name inside [corpusDirectory].
  final String fileName;

  /// Decoded width in pixels.
  final int width;

  /// Decoded height in pixels.
  final int height;

  /// Faces the cascade is expected to report.
  final List<ExpectedFace> expectedFaces;

  /// Face-size floor needed to reach the faces in this image.
  final double minimumFaceSize;

  /// Accuracy presets this entry is checked against.
  final List<FaceDetectionAccuracy> accuracies;

  /// Why this entry exists, when that is not obvious from its name.
  final String? note;

  /// Reads the encoded bytes of this entry.
  Uint8List readBytes() => File('$corpusDirectory/$fileName').readAsBytesSync();

  /// Options that reproduce the reference results for this entry.
  FaceDetectorOptions optionsFor(FaceDetectionAccuracy accuracy) => FaceDetectorOptions(
    accuracy: accuracy,
    minimumFaceSize: minimumFaceSize,
    maximumFaces: 40,
    runInIsolate: false,
  );
}

/// Public-domain reference images and their expected detections.
///
/// Every reference box was read back from the detector and checked by hand
/// against the photograph. Attribution and licensing live in
/// `test/corpus/README.md`.
const List<CorpusEntry> corpus = <CorpusEntry>[
  CorpusEntry(
    fileName: 'portrait_michelle_obama.jpg',
    width: 500,
    height: 752,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 243,
        centerY: 211,
        size: 106,
        landmarks: ExpectedLandmarks(leftEyeX: 217.5, leftEyeY: 183, rightEyeX: 271, rightEyeY: 183, mouthX: 240, mouthY: 239.5),
      ),
    ],
  ),
  CorpusEntry(
    fileName: 'portrait_sally_ride.jpg',
    width: 500,
    height: 625,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 259,
        centerY: 224,
        size: 103,
        landmarks: ExpectedLandmarks(leftEyeX: 228.5, leftEyeY: 196, rightEyeX: 289, rightEyeY: 198, mouthX: 257.5, mouthY: 253),
      ),
    ],
  ),
  CorpusEntry(
    fileName: 'portrait_marie_curie.jpg',
    width: 500,
    height: 679,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 221,
        centerY: 305,
        size: 148,
        landmarks: ExpectedLandmarks(leftEyeX: 179, leftEyeY: 263.5, rightEyeX: 272, rightEyeY: 264, mouthX: 225, mouthY: 362.5),
      ),
    ],
    note: 'A century-old monochrome photograph, so the color heuristics cannot help.',
  ),
  CorpusEntry(
    fileName: 'portrait_katherine_johnson.jpg',
    width: 500,
    height: 625,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 219,
        centerY: 243,
        size: 134,
        landmarks: ExpectedLandmarks(leftEyeX: 185.5, leftEyeY: 213, rightEyeX: 253.5, rightEyeY: 205, mouthX: 226, mouthY: 286),
      ),
    ],
  ),
  CorpusEntry(
    fileName: 'portrait_mae_jemison.jpg',
    width: 500,
    height: 625,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 292,
        centerY: 163,
        size: 85,
        landmarks: ExpectedLandmarks(
          leftEyeX: 270,
          leftEyeY: 139.5,
          rightEyeX: 314,
          rightEyeY: 139,
          mouthX: 292,
          mouthY: 180,
        ),
        landmarksUsedForTuning: false,
      ),
    ],
    note: 'A smiling dark-skinned subject against a low-detail studio background.',
  ),
  CorpusEntry(
    fileName: 'portrait_albert_einstein.jpg',
    width: 500,
    height: 667,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 291,
        centerY: 310,
        size: 190,
        landmarks: ExpectedLandmarks(leftEyeX: 237, leftEyeY: 256.5, rightEyeX: 331, rightEyeY: 257.5, mouthX: 291, mouthY: 382),
      ),
    ],
  ),
  CorpusEntry(
    fileName: 'portrait_buzz_aldrin.jpg',
    width: 500,
    height: 625,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 289,
        centerY: 204,
        size: 64,
        landmarks: ExpectedLandmarks(leftEyeX: 272, leftEyeY: 186, rightEyeX: 307, rightEyeY: 183, mouthX: 290.5, mouthY: 222.5),
      ),
    ],
    minimumFaceSize: 0.10,
    accuracies: <FaceDetectionAccuracy>[FaceDetectionAccuracy.balanced, FaceDetectionAccuracy.accurate],
    note: 'A small face inside a pressure helmet; fast skips this size.',
  ),
  CorpusEntry(
    fileName: 'portrait_neil_armstrong.jpg',
    width: 500,
    height: 625,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 304,
        centerY: 181,
        size: 67,
        landmarks: ExpectedLandmarks(leftEyeX: 286.5, leftEyeY: 165.5, rightEyeX: 321, rightEyeY: 158.5, mouthX: 307.5, mouthY: 199),
      ),
    ],
    minimumFaceSize: 0.10,
    accuracies: <FaceDetectionAccuracy>[FaceDetectionAccuracy.balanced, FaceDetectionAccuracy.accurate],
    note: 'A small face inside a pressure helmet; fast skips this size.',
  ),
  CorpusEntry(
    fileName: 'portrait_ruth_bader_ginsburg.jpg',
    width: 304,
    height: 394,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 152,
        centerY: 128,
        size: 75,
        landmarks: ExpectedLandmarks(
          leftEyeX: 130.5,
          leftEyeY: 107.5,
          rightEyeX: 174.5,
          rightEyeY: 105.5,
          mouthX: 155,
          mouthY: 152,
        ),
        landmarksUsedForTuning: false,
      ),
    ],
    note: 'An older subject wearing rimmed glasses in front of a textured background.',
  ),
  CorpusEntry(
    fileName: 'group_apollo11_crew.jpg',
    width: 960,
    height: 754,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(
        centerX: 464,
        centerY: 184,
        size: 65,
        landmarks: ExpectedLandmarks(leftEyeX: 445.5, leftEyeY: 166, rightEyeX: 480, rightEyeY: 165, mouthX: 465.5, mouthY: 202),
        landmarksUsedForTuning: false,
      ),
      ExpectedFace(
        centerX: 249,
        centerY: 320,
        size: 65,
        landmarks: ExpectedLandmarks(leftEyeX: 229.5, leftEyeY: 303.5, rightEyeX: 264.5, rightEyeY: 303.5, mouthX: 243.5, mouthY: 337.5),
        landmarksUsedForTuning: false,
      ),
      ExpectedFace(
        centerX: 687,
        centerY: 333,
        size: 65,
        landmarks: ExpectedLandmarks(leftEyeX: 671, leftEyeY: 316.5, rightEyeX: 704.5, rightEyeY: 314, mouthX: 692, mouthY: 350.5),
        landmarksUsedForTuning: false,
      ),
    ],
    minimumFaceSize: 0.05,
    accuracies: <FaceDetectionAccuracy>[FaceDetectionAccuracy.accurate],
    note:
        'Three faces well under a tenth of the frame. Their landmarks were labelled '
        'after the landmark estimator was tuned, so they validate it on faces that '
        'took no part in that tuning.',
  ),
  CorpusEntry(
    fileName: 'group_obama_family.jpg',
    width: 960,
    height: 540,
    expectedFaces: <ExpectedFace>[
      ExpectedFace(centerX: 220, centerY: 163, size: 90),
      ExpectedFace(centerX: 411, centerY: 193, size: 90),
      ExpectedFace(centerX: 642, centerY: 163, size: 95),
      ExpectedFace(centerX: 750, centerY: 269, size: 98),
    ],
    minimumFaceSize: 0.05,
    accuracies: <FaceDetectionAccuracy>[FaceDetectionAccuracy.accurate],
    note:
        'Four faces with different skin tones; the strongly rolled rightmost '
        'face exercises accurate-mode rotation recovery.',
  ),
];

/// Images that must not produce any detection.
const List<CorpusEntry> negativeCorpus = <CorpusEntry>[
  CorpusEntry(
    fileName: 'negative_big_bend.jpg',
    width: 500,
    height: 374,
    expectedFaces: <ExpectedFace>[],
    note: 'A landscape with sky, rock, and vegetation textures.',
  ),
  CorpusEntry(
    fileName: 'negative_blue_marble.png',
    width: 500,
    height: 250,
    expectedFaces: <ExpectedFace>[],
    note: 'A rendered globe with a large smooth ellipse on a black ground.',
  ),
  CorpusEntry(
    fileName: 'negative_usda_lab_cat.jpg',
    width: 500,
    height: 383,
    expectedFaces: <ExpectedFace>[],
    note: 'A frontal animal face with paired eyes and approximate bilateral symmetry.',
  ),
  CorpusEntry(
    fileName: 'negative_statue_of_liberty_face.jpg',
    width: 500,
    height: 559,
    expectedFaces: <ExpectedFace>[],
    accuracies: <FaceDetectionAccuracy>[FaceDetectionAccuracy.accurate],
    note: 'A highly face-like metal sculpture that accurate mode must reject.',
  ),
];
