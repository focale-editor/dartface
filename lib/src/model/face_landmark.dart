import 'package:dartface/src/model/face_point.dart';

/// Identifies a landmark estimated by the detector.
enum FaceLandmarkType {
  /// Eye shown on the left side of the image.
  leftEye,

  /// Eye shown on the right side of the image.
  rightEye,

  /// Approximate tip of the nose.
  noseTip,

  /// Left corner of the mouth as shown in the image.
  mouthLeft,

  /// Center of the mouth.
  mouthCenter,

  /// Right corner of the mouth as shown in the image.
  mouthRight,
}

/// A facial landmark and the detector's confidence in its location.
final class FaceLandmark {
  /// Creates a landmark at [position].
  const FaceLandmark({
    required this.position,
    required this.confidence,
  }) : assert(confidence >= 0 && confidence <= 1, 'confidence must be between zero and one');

  /// Landmark position in source-image pixels.
  final FacePoint position;

  /// Location confidence from zero to one.
  final double confidence;

  /// Returns this landmark scaled independently on both axes.
  FaceLandmark scaled({
    required double scaleX,
    required double scaleY,
  }) => FaceLandmark(
    position: position.scaled(scaleX: scaleX, scaleY: scaleY),
    confidence: confidence,
  );

  @override
  String toString() => 'FaceLandmark(position: $position, confidence: $confidence)';
}
