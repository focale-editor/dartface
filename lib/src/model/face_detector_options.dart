/// Chooses the speed and recall trade-off used during multi-scale scanning.
enum FaceDetectionAccuracy {
  /// Uses a smaller working image and wider scan steps.
  fast,

  /// Balances latency and recall for interactive applications.
  balanced,

  /// Uses a larger working image and denser scan steps.
  accurate,
}

/// Configures face candidate generation and filtering.
final class FaceDetectorOptions {
  /// Creates detector options.
  const FaceDetectorOptions({
    this.accuracy = FaceDetectionAccuracy.balanced,
    this.minimumFaceSize = 0.15,
    this.maximumFaceSize = 0.95,
    this.confidenceThreshold = 0.58,
    this.minimumLandmarkConfidence = 0.40,
    this.maximumFaces = 10,
    this.runInIsolate = true,
    this.maximumDecodedPixels = 40000000,
    this.enableRotationRecovery = true,
    this.enableHeuristicFallback = false,
  }) : assert(minimumFaceSize == minimumFaceSize && minimumFaceSize > 0 && minimumFaceSize <= 1, 'minimumFaceSize must be finite and in the range (0, 1]'),
       assert(maximumFaceSize == maximumFaceSize && maximumFaceSize > 0 && maximumFaceSize <= 1, 'maximumFaceSize must be finite and in the range (0, 1]'),
       assert(minimumFaceSize <= maximumFaceSize, 'minimumFaceSize must not exceed maximumFaceSize'),
       assert(confidenceThreshold == confidenceThreshold && confidenceThreshold >= 0 && confidenceThreshold <= 1, 'confidenceThreshold must be finite and between zero and one'),
       assert(
         minimumLandmarkConfidence == minimumLandmarkConfidence && minimumLandmarkConfidence >= 0 && minimumLandmarkConfidence <= 1,
         'minimumLandmarkConfidence must be finite and between zero and one',
       ),
       assert(maximumFaces > 0, 'maximumFaces must be positive'),
       assert(maximumDecodedPixels > 0, 'maximumDecodedPixels must be positive');

  /// Amount of multi-scale work performed for each image.
  final FaceDetectionAccuracy accuracy;

  /// Smallest accepted face height as a fraction of the shortest image edge.
  final double minimumFaceSize;

  /// Largest accepted face height as a fraction of the shortest image edge.
  final double maximumFaceSize;

  /// Minimum confidence returned to the caller.
  final double confidenceThreshold;

  /// Minimum mean confidence required across the six estimated landmarks.
  ///
  /// Set this to zero to disable the filter on the primary pass. The default
  /// discards sparse geometry that is too uncertain for photo editing;
  /// rotation recovery retains the safety floor documented below.
  final double minimumLandmarkConfidence;

  /// Maximum number of results returned per image.
  final int maximumFaces;

  /// Whether asynchronous methods should move CPU work off the UI isolate.
  final bool runInIsolate;

  /// Maximum number of pixels accepted from an encoded image.
  final int maximumDecodedPixels;

  /// Whether accurate mode should recover faces rotated about fifteen degrees.
  ///
  /// The two extra deskewed passes improve tilted and group portraits. They use
  /// internal safety floors of 0.75 for the box and 0.35 for landmarks, and
  /// are ignored by the fast and balanced modes.
  final bool enableRotationRecovery;

  /// Whether to try the experimental color-and-structure detector when the
  /// frontal-face cascade finds no face.
  ///
  /// This can recognize drawings and unusual image styles, but it also
  /// increases the risk of false positives. Keep it disabled for photos.
  final bool enableHeuristicFallback;
}
