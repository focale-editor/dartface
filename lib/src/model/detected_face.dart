import 'dart:collection';

import 'package:dartface/src/model/face_bounding_box.dart';
import 'package:dartface/src/model/face_landmark.dart';

/// A face detected in an image.
final class DetectedFace {
  /// Creates an immutable detection result.
  DetectedFace({
    required this.boundingBox,
    required this.confidence,
    required Map<FaceLandmarkType, FaceLandmark> landmarks,
    required this.imageWidth,
    required this.imageHeight,
    required this.rollDegrees,
  }) : assert(confidence >= 0 && confidence <= 1, 'confidence must be between zero and one'),
       assert(imageWidth > 0, 'imageWidth must be positive'),
       assert(imageHeight > 0, 'imageHeight must be positive'),
       landmarks = UnmodifiableMapView(Map<FaceLandmarkType, FaceLandmark>.of(landmarks));

  /// Region containing the face in source-image pixels.
  final FaceBoundingBox boundingBox;

  /// Detection confidence from zero to one.
  final double confidence;

  /// Estimated sparse landmarks keyed by their semantic role.
  final Map<FaceLandmarkType, FaceLandmark> landmarks;

  /// Width of the source image in pixels.
  final int imageWidth;

  /// Height of the source image in pixels.
  final int imageHeight;

  /// In-plane head rotation in degrees, positive clockwise in image space.
  final double rollDegrees;

  /// Alias matching detector APIs that call detection confidence a score.
  double get score => confidence;

  /// Mean confidence across the available sparse landmarks.
  ///
  /// This score is separate from [confidence], which describes the face box.
  /// A caller that deforms facial features should check both values.
  double get landmarkConfidence {
    if (landmarks.isEmpty) {
      return 0;
    }
    final double confidenceSum = landmarks.values.fold(
      0.0,
      (sum, landmark) => sum + landmark.confidence,
    );
    return confidenceSum / landmarks.length;
  }

  /// Face width as a fraction of the source image width.
  double get widthFraction => boundingBox.width / imageWidth;

  /// Returns the requested landmark when it could be estimated.
  FaceLandmark? landmark(FaceLandmarkType type) => landmarks[type];

  @override
  String toString() => 'DetectedFace(boundingBox: $boundingBox, confidence: $confidence, rollDegrees: $rollDegrees)';
}

/// Short name for a [DetectedFace], useful while migrating from other detectors.
typedef Face = DetectedFace;
