import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartface/src/detector/lbp_cascade_detector.dart';
import 'package:dartface/src/image/analysis_image.dart';
import 'package:dartface/src/image/integral_plane.dart';
import 'package:dartface/src/model/detected_face.dart';
import 'package:dartface/src/model/face_bounding_box.dart';
import 'package:dartface/src/model/face_detector_options.dart';
import 'package:dartface/src/model/face_landmark.dart';
import 'package:dartface/src/model/face_point.dart';

/// Detects frontal faces with a cascade and estimates sparse landmarks.
final class ClassicalFaceDetectionEngine {
  /// Creates a stateless detection engine.
  const ClassicalFaceDetectionEngine();

  /// Small clockwise and counter-clockwise deskew passes used by accurate mode.
  static const List<double> _rotationRecoveryAngles = <double>[
    -math.pi / 12,
    math.pi / 12,
  ];

  /// Longest edge used by secondary deskew passes.
  static const int _rotationRecoveryMaximumDimension = 640;

  /// Searches [rgbaBytes] for faces according to [options].
  List<DetectedFace> detect({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required FaceDetectorOptions options,
  }) {
    _validateOptions(options);
    final _ScanProfile profile = _profileFor(options.accuracy);
    final AnalysisImage image = AnalysisImage.fromRgba(
      bytes: rgbaBytes,
      width: width,
      height: height,
      maximumDimension: profile.maximumDimension,
    );
    final List<_FaceProposal> proposals = <_FaceProposal>[
      for (final DetectedFace face in _detectWithCascade(
        image: image,
        options: options,
      ))
        _FaceProposal(face: face, isRecovery: false),
    ];
    if (options.accuracy == FaceDetectionAccuracy.accurate && options.enableRotationRecovery) {
      final FaceDetectorOptions recoveryOptions = _rotationRecoveryOptions(
        options,
      );
      for (final double angleRadians in _rotationRecoveryAngles) {
        final AnalysisImage rotatedImage = AnalysisImage.fromRotatedRgba(
          bytes: rgbaBytes,
          width: width,
          height: height,
          maximumDimension: math.min(
            profile.maximumDimension,
            _rotationRecoveryMaximumDimension,
          ),
          angleRadians: angleRadians,
        );
        for (final DetectedFace face in _detectWithCascade(
          image: rotatedImage,
          options: recoveryOptions,
        )) {
          proposals.add(
            _FaceProposal(
              face: _restoreRotation(
                face,
                angleRadians: angleRadians,
              ),
              isRecovery: true,
            ),
          );
        }
      }
    }
    if (proposals.isNotEmpty) {
      return _suppressFaceOverlaps(
        proposals: proposals,
        maximumFaces: options.maximumFaces,
      );
    }
    if (!options.enableHeuristicFallback) {
      return const <DetectedFace>[];
    }

    return _detectWithHeuristics(
      image: image,
      options: options,
      profile: profile,
    );
  }

  /// Runs the trained cascade and validates the sparse geometry it produces.
  List<DetectedFace> _detectWithCascade({
    required AnalysisImage image,
    required FaceDetectorOptions options,
  }) {
    final List<LbpDetection> cascadeDetections = const LbpCascadeDetector().detect(
      image: image,
      options: options,
    );
    final List<_DetectionCandidate> cascadeCandidates = <_DetectionCandidate>[];
    for (final LbpDetection detection in cascadeDetections) {
      if (detection.confidence < options.confidenceThreshold) {
        continue;
      }
      final _DetectionCandidate? candidate = _candidateFromCascade(
        image: image,
        detection: detection,
      );
      if (candidate != null && candidate.landmarkConfidence >= options.minimumLandmarkConfidence) {
        cascadeCandidates.add(candidate);
      }
    }
    cascadeCandidates.sort(
      (first, second) => second.confidence.compareTo(first.confidence),
    );
    return _suppressOverlaps(
      image: image,
      candidates: cascadeCandidates,
      maximumFaces: options.maximumFaces,
    );
  }

  /// Converts one cascade pass to a face candidate with estimated landmarks.
  _DetectionCandidate? _candidateFromCascade({
    required AnalysisImage image,
    required LbpDetection detection,
  }) {
    final int left = detection.left.floor().clamp(0, image.width - 1);
    final int top = detection.top.floor().clamp(0, image.height - 1);
    final int right = (detection.left + detection.width).ceil().clamp(left + 1, image.width);
    final int bottom = (detection.top + detection.height).ceil().clamp(top + 1, image.height);
    final _ScanWindow window = _ScanWindow(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
    final double mean = image.luminanceIntegral.mean(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    final double squaredMean = image.squaredLuminanceIntegral.mean(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    final double standardDeviation = math.sqrt(math.max(0, squaredMean - mean * mean));
    return _evaluateLandmarks(
      image: image,
      preliminary: _WindowScore(
        window: window,
        score: detection.confidence,
        standardDeviation: standardDeviation,
        eyeContrast: 0.5,
        mouthScore: 0.5,
      ),
      geometry: _LandmarkGeometry.cascade,
      trustedConfidence: detection.confidence,
    );
  }

  /// Runs the opt-in color-and-structure detector after a cascade miss.
  List<DetectedFace> _detectWithHeuristics({
    required AnalysisImage image,
    required FaceDetectorOptions options,
    required _ScanProfile profile,
  }) {
    final List<_WindowScore> preliminary = _scan(image: image, options: options, profile: profile);
    preliminary.sort((first, second) => second.score.compareTo(first.score));
    final int evaluationCount = math.min(profile.maximumEvaluatedWindows, preliminary.length);
    final List<_DetectionCandidate> candidates = <_DetectionCandidate>[];
    for (int index = 0; index < evaluationCount; index++) {
      final _DetectionCandidate? candidate = _evaluateLandmarks(image: image, preliminary: preliminary[index], geometry: _LandmarkGeometry.heuristic);
      if (candidate != null && candidate.confidence >= options.confidenceThreshold && candidate.landmarkConfidence >= options.minimumLandmarkConfidence) {
        candidates.add(candidate);
      }
    }
    candidates.sort((first, second) => second.confidence.compareTo(first.confidence));
    return _suppressOverlaps(image: image, candidates: candidates, maximumFaces: options.maximumFaces);
  }

  /// Generates inexpensive multi-scale candidates before landmark searches.
  List<_WindowScore> _scan({
    required AnalysisImage image,
    required FaceDetectorOptions options,
    required _ScanProfile profile,
  }) {
    final int shortestEdge = math.min(image.width, image.height);
    final int minimumHeight = math.max(24, (shortestEdge * options.minimumFaceSize).round());
    final int maximumHeight = math.max(minimumHeight, math.min(image.height, (shortestEdge * options.maximumFaceSize).round()));
    final List<_WindowScore> scores = <_WindowScore>[];
    double currentHeight = minimumHeight.toDouble();
    while (currentHeight <= maximumHeight + 0.5) {
      final int windowHeight = currentHeight.round();
      for (final double aspectRatio in profile.aspectRatios) {
        final int windowWidth = (windowHeight * aspectRatio).round();
        if (windowWidth > image.width || windowWidth < 18) {
          continue;
        }
        final int horizontalStep = math.max(2, (windowWidth * profile.stepFraction).round());
        final int verticalStep = math.max(2, (windowHeight * profile.stepFraction).round());
        for (int top = 0; top <= image.height - windowHeight; top += verticalStep) {
          for (int left = 0; left <= image.width - windowWidth; left += horizontalStep) {
            final _ScanWindow window = _ScanWindow(left: left, top: top, width: windowWidth, height: windowHeight);
            final _WindowScore? score = _scoreStructure(image: image, window: window);
            if (score != null && score.score >= math.max(0.30, options.confidenceThreshold - 0.24)) {
              scores.add(score);
            }
          }
        }
      }
      currentHeight *= profile.pyramidFactor;
    }
    return scores;
  }

  /// Scores color layout, contrast, symmetry, and coarse facial structure.
  _WindowScore? _scoreStructure({required AnalysisImage image, required _ScanWindow window}) {
    final double mean = _mean(image.luminanceIntegral, window, 0, 0, 1, 1);
    final double squaredMean = _mean(image.squaredLuminanceIntegral, window, 0, 0, 1, 1);
    final double variance = math.max(0, squaredMean - mean * mean);
    final double standardDeviation = math.sqrt(variance);
    if (standardDeviation < 7 || standardDeviation > 105) {
      return null;
    }

    final double leftEyeMean = _mean(image.luminanceIntegral, window, 0.12, 0.27, 0.44, 0.48);
    final double rightEyeMean = _mean(image.luminanceIntegral, window, 0.56, 0.27, 0.88, 0.48);
    final double leftCheekMean = _mean(image.luminanceIntegral, window, 0.14, 0.48, 0.43, 0.68);
    final double rightCheekMean = _mean(image.luminanceIntegral, window, 0.57, 0.48, 0.86, 0.68);
    final double cheekMean = (leftCheekMean + rightCheekMean) / 2;
    final double eyeMean = (leftEyeMean + rightEyeMean) / 2;
    final double noseMean = _mean(image.luminanceIntegral, window, 0.41, 0.40, 0.59, 0.68);
    final double mouthMean = _mean(image.luminanceIntegral, window, 0.25, 0.68, 0.75, 0.86);
    final double lowerFaceMean = _mean(image.luminanceIntegral, window, 0.18, 0.56, 0.82, 0.94);

    final double eyeContrast = ((cheekMean - eyeMean) / (standardDeviation * 0.48 + 4) + 0.08).clamp(0, 1);
    final double eyeBalance = (1 - (leftEyeMean - rightEyeMean).abs() / (standardDeviation * 1.15 + 7)).clamp(0, 1);
    final double noseContrast = ((noseMean - eyeMean) / (standardDeviation * 0.62 + 5) + 0.12).clamp(0, 1);
    final double mouthDarkness = ((lowerFaceMean - mouthMean) / (standardDeviation * 0.45 + 4) + 0.10).clamp(0, 1);
    final double mouthRedness = _mean(image.rednessIntegral, window, 0.24, 0.67, 0.76, 0.87);
    final double mouthScore = (0.74 * mouthDarkness + 0.26 * (mouthRedness * 1.7).clamp(0, 1)).clamp(0, 1);
    if (eyeContrast < 0.10 || eyeBalance < 0.30 || noseContrast < 0.08 || mouthScore < 0.08) {
      return null;
    }

    final double centerSkin = _mean(image.skinIntegral, window, 0.14, 0.12, 0.86, 0.91);
    final double cornerSkin =
        (_mean(image.skinIntegral, window, 0, 0, 0.18, 0.22) +
            _mean(image.skinIntegral, window, 0.82, 0, 1, 0.22) +
            _mean(image.skinIntegral, window, 0, 0.76, 0.18, 1) +
            _mean(image.skinIntegral, window, 0.82, 0.76, 1, 1)) /
        4;
    final bool monochrome = image.colorfulness < 0.025;
    if (!monochrome && centerSkin < 0.24) {
      return null;
    }
    final double skinScore = monochrome ? 0.52 : ((centerSkin - 0.18) / 0.58).clamp(0, 1);
    final double ovalScore = monochrome ? 0.50 : ((centerSkin - cornerSkin + 0.08) / 0.34).clamp(0, 1);
    final double symmetryScore = _symmetryScore(image: image, window: window, standardDeviation: standardDeviation);
    final double textureScore = math.min(((standardDeviation - 6) / 24).clamp(0, 1), ((108 - standardDeviation) / 36).clamp(0, 1));
    final double score = 0.19 * skinScore + 0.07 * ovalScore + 0.20 * eyeContrast + 0.08 * eyeBalance + 0.13 * noseContrast + 0.14 * mouthScore + 0.12 * symmetryScore + 0.07 * textureScore;
    return _WindowScore(
      window: window,
      score: score,
      standardDeviation: standardDeviation,
      eyeContrast: eyeContrast,
      mouthScore: mouthScore,
    );
  }

  /// Locates sparse landmarks and folds their geometry into final confidence.
  _DetectionCandidate? _evaluateLandmarks({
    required AnalysisImage image,
    required _WindowScore preliminary,
    required _LandmarkGeometry geometry,
    double? trustedConfidence,
  }) {
    final _ScanWindow window = preliminary.window;
    final _FeaturePoint leftEye = _findDarkFeature(
      image: image,
      window: window,
      leftFraction: geometry.eyeOuterFraction,
      topFraction: geometry.eyeTopFraction,
      rightFraction: geometry.eyeInnerFraction,
      bottomFraction: geometry.eyeBottomFraction,
      expectedX: geometry.expectedLeftEyeX,
      expectedY: geometry.expectedEyeY,
      standardDeviation: preliminary.standardDeviation,
      priorStrength: geometry.priorStrength,
    );
    final _FeaturePoint rightEye = _findDarkFeature(
      image: image,
      window: window,
      leftFraction: 1 - geometry.eyeInnerFraction,
      topFraction: geometry.eyeTopFraction,
      rightFraction: 1 - geometry.eyeOuterFraction,
      bottomFraction: geometry.eyeBottomFraction,
      expectedX: 1 - geometry.expectedLeftEyeX,
      expectedY: geometry.expectedEyeY,
      standardDeviation: preliminary.standardDeviation,
      priorStrength: geometry.priorStrength,
    );
    // A near-frontal face is close to symmetric, and the eyes are located far
    // more reliably than the mouth, whose darkest points are its corners and
    // the shadows around it. So the mouth is searched in a narrow band under
    // the eye midpoint rather than across the whole lower window.
    final double eyeMidpointFraction = ((leftEye.x + rightEye.x) / 2 - window.left) / window.width;
    final double mouthCenterFraction = geometry.mouthFollowsEyeMidpoint ? eyeMidpointFraction.clamp(0.3, 0.7) : 0.5;
    final _FeaturePoint mouth = _findDarkFeature(
      image: image,
      window: window,
      leftFraction: math.max(0, mouthCenterFraction - geometry.mouthHalfWidth),
      topFraction: geometry.mouthTopFraction,
      rightFraction: math.min(1, mouthCenterFraction + geometry.mouthHalfWidth),
      bottomFraction: geometry.mouthBottomFraction,
      expectedX: mouthCenterFraction,
      expectedY: geometry.expectedMouthY,
      standardDeviation: preliminary.standardDeviation,
      priorStrength: geometry.priorStrength,
      rednessWeight: 0.42,
      radiusXFraction: geometry.mouthRadiusXFraction,
    );

    final double eyeSeparation = (rightEye.x - leftEye.x) / window.width;
    final double eyeSeparationScore = (1 - (eyeSeparation - geometry.expectedEyeSeparation).abs() / 0.19).clamp(0, 1);
    final double eyeAlignmentScore = (1 - (rightEye.y - leftEye.y).abs() / (window.height * 0.14)).clamp(0, 1);
    final double mouthCenteringScore = (1 - ((mouth.x - (leftEye.x + rightEye.x) / 2) / (window.width * 0.28)).abs()).clamp(0, 1);
    final double eyeLine = (leftEye.y + rightEye.y) / 2;
    final double mouthSpacing = (mouth.y - eyeLine) / window.height;
    final double mouthSpacingScore = (1 - (mouthSpacing - geometry.expectedMouthSpacing).abs() / 0.19).clamp(0, 1);
    final double geometryScore = (eyeSeparationScore + eyeAlignmentScore + mouthCenteringScore + mouthSpacingScore) / 4;
    final double featureConfidence = (leftEye.confidence + rightEye.confidence + mouth.confidence) / 3;
    if (trustedConfidence == null && (eyeSeparationScore < 0.18 || eyeAlignmentScore < 0.35 || mouthCenteringScore < 0.50 || mouthSpacingScore < 0.16 || featureConfidence < 0.08)) {
      return null;
    }
    final double finalConfidence = trustedConfidence ?? (preliminary.score * 0.78 + geometryScore * 0.16 + featureConfidence * 0.06).clamp(0, 1);
    final double noseX = (leftEye.x + rightEye.x) / 2;
    final double noseY = eyeLine + (mouth.y - eyeLine) * 0.54;
    final double noseConfidence = (geometryScore * 0.7 + featureConfidence * 0.3).clamp(0, 1);
    final double mouthHalfWidth = window.width * (geometry.mouthCornerFraction + 0.05 * preliminary.mouthScore);
    final Map<FaceLandmarkType, _FeaturePoint> landmarks = <FaceLandmarkType, _FeaturePoint>{
      FaceLandmarkType.leftEye: leftEye,
      FaceLandmarkType.rightEye: rightEye,
      FaceLandmarkType.noseTip: _FeaturePoint(
        x: noseX,
        y: noseY,
        confidence: noseConfidence,
      ),
      FaceLandmarkType.mouthLeft: _FeaturePoint(
        x: mouth.x - mouthHalfWidth,
        y: mouth.y,
        confidence: mouth.confidence * 0.85,
      ),
      FaceLandmarkType.mouthCenter: mouth,
      FaceLandmarkType.mouthRight: _FeaturePoint(
        x: mouth.x + mouthHalfWidth,
        y: mouth.y,
        confidence: mouth.confidence * 0.85,
      ),
    };
    final double landmarkConfidence =
        landmarks.values.fold(
          0.0,
          (sum, landmark) => sum + landmark.confidence,
        ) /
        landmarks.length;
    return _DetectionCandidate(
      window: window,
      confidence: finalConfidence,
      landmarkConfidence: landmarkConfidence,
      landmarks: landmarks,
    );
  }

  /// Finds the strongest locally dark response in a fractional window region.
  _FeaturePoint _findDarkFeature({
    required AnalysisImage image,
    required _ScanWindow window,
    required double leftFraction,
    required double topFraction,
    required double rightFraction,
    required double bottomFraction,
    required double expectedX,
    required double expectedY,
    required double standardDeviation,
    required double priorStrength,
    double rednessWeight = 0,
    double radiusXFraction = 0.055,
  }) {
    final int left = window.left + (window.width * leftFraction).floor();
    final int top = window.top + (window.height * topFraction).floor();
    final int right = window.left + (window.width * rightFraction).ceil();
    final int bottom = window.top + (window.height * bottomFraction).ceil();
    final int radiusX = math.max(1, (window.width * radiusXFraction).round());
    final int radiusY = math.max(1, (window.height * 0.035).round());
    final double referenceMean = _mean(image.luminanceIntegral, window, leftFraction, topFraction, rightFraction, bottomFraction);
    final IntegralPlane luminanceIntegral = image.luminanceIntegral;
    final double darknessScale = standardDeviation * 0.72 + 5;
    double bestResponse = -double.infinity;
    int bestX = ((left + right) / 2).round();
    int bestY = ((top + bottom) / 2).round();
    for (int y = top; y < bottom; y++) {
      final int neighborhoodTop = math.max(window.top, y - radiusY);
      final int neighborhoodBottom = math.min(window.bottom, y + radiusY + 1);
      final double verticalOffset = (y - window.top) / window.height - expectedY;
      for (int x = left; x < right; x++) {
        final double localMean = luminanceIntegral.mean(
          left: math.max(window.left, x - radiusX),
          top: neighborhoodTop,
          right: math.min(window.right, x + radiusX + 1),
          bottom: neighborhoodBottom,
        );
        final double featureLuminance = localMean * 0.82 + image.luminanceAt(x, y) * 0.18;
        final double darkness = (referenceMean - featureLuminance) / darknessScale;
        final double horizontalOffset = (x - window.left) / window.width - expectedX;
        final double distancePenalty = math.sqrt(horizontalOffset * horizontalOffset + verticalOffset * verticalOffset) * priorStrength;
        final double response = darkness + (rednessWeight == 0 ? 0 : rednessWeight * image.rednessAt(x, y)) - distancePenalty;
        if (response > bestResponse) {
          bestResponse = response;
          bestX = x;
          bestY = y;
        }
      }
    }
    final double confidence = ((bestResponse + 0.12) / 0.88).clamp(0, 1);
    return _FeaturePoint(x: bestX.toDouble(), y: bestY.toDouble(), confidence: confidence);
  }

  /// Measures bilateral luminance agreement on a coarse spatial grid.
  double _symmetryScore({required AnalysisImage image, required _ScanWindow window, required double standardDeviation}) {
    double differenceSum = 0;
    int comparisons = 0;
    for (int row = 1; row <= 8; row++) {
      final int y = math.min(window.bottom - 1, window.top + (window.height * row / 10).round());
      for (int column = 1; column <= 4; column++) {
        final int leftX = math.min(window.right - 1, window.left + (window.width * column / 10).round());
        final int rightX = math.max(window.left, window.right - 1 - (leftX - window.left));
        differenceSum += (image.luminanceAt(leftX, y) - image.luminanceAt(rightX, y)).abs();
        comparisons++;
      }
    }
    final double averageDifference = differenceSum / comparisons;
    return (1 - averageDifference / (standardDeviation * 1.35 + 9)).clamp(0, 1);
  }

  /// Converts fractional window bounds to an integral-plane mean.
  double _mean(
    IntegralPlane plane,
    _ScanWindow window,
    double leftFraction,
    double topFraction,
    double rightFraction,
    double bottomFraction,
  ) {
    final int left = (window.left + window.width * leftFraction).floor().clamp(window.left, window.right - 1);
    final int top = (window.top + window.height * topFraction).floor().clamp(window.top, window.bottom - 1);
    final int right = (window.left + window.width * rightFraction).ceil().clamp(left + 1, window.right);
    final int bottom = (window.top + window.height * bottomFraction).ceil().clamp(top + 1, window.bottom);
    return plane.mean(left: left, top: top, right: right, bottom: bottom);
  }

  /// Removes nested and highly overlapping windows, then maps to source pixels.
  List<DetectedFace> _suppressOverlaps({
    required AnalysisImage image,
    required List<_DetectionCandidate> candidates,
    required int maximumFaces,
  }) {
    final List<_DetectionCandidate> selected = <_DetectionCandidate>[];
    for (final _DetectionCandidate candidate in candidates) {
      final bool overlaps = selected.any((existing) {
        final double intersection = candidate.window.intersectionArea(existing.window);
        final double union = candidate.window.area + existing.window.area - intersection;
        final double intersectionOverUnion = union == 0 ? 0 : intersection / union;
        final double containment = intersection / math.min(candidate.window.area, existing.window.area);
        return intersectionOverUnion > 0.32 || containment > 0.68;
      });
      if (!overlaps) {
        selected.add(candidate);
      }
      if (selected.length == maximumFaces) {
        break;
      }
    }

    return <DetectedFace>[
      for (final _DetectionCandidate candidate in selected) _toDetectedFace(image: image, candidate: candidate),
    ];
  }

  /// Merges primary and deskewed source-space detections.
  List<DetectedFace> _suppressFaceOverlaps({
    required List<_FaceProposal> proposals,
    required int maximumFaces,
  }) {
    final List<_FaceProposal> sorted = List<_FaceProposal>.of(proposals)
      ..sort((first, second) {
        if (first.isRecovery != second.isRecovery) {
          return first.isRecovery ? 1 : -1;
        }
        return second.quality.compareTo(first.quality);
      });
    final List<DetectedFace> selected = <DetectedFace>[];
    for (final _FaceProposal proposal in sorted) {
      final FaceBoundingBox box = proposal.face.boundingBox;
      final bool overlaps = selected.any((face) {
        final FaceBoundingBox existing = face.boundingBox;
        final double intersectionLeft = math.max(box.left, existing.left);
        final double intersectionTop = math.max(box.top, existing.top);
        final double intersectionRight = math.min(box.right, existing.right);
        final double intersectionBottom = math.min(box.bottom, existing.bottom);
        final double intersection = math.max(0, intersectionRight - intersectionLeft) * math.max(0, intersectionBottom - intersectionTop);
        final double smallerArea = math.min(box.area, existing.area);
        final double containment = smallerArea == 0 ? 0 : intersection / smallerArea;
        return box.intersectionOverUnion(existing) > 0.30 || containment > 0.66;
      });
      if (!overlaps) {
        selected.add(proposal.face);
      }
      if (selected.length == maximumFaces) {
        break;
      }
    }
    return selected;
  }

  /// Maps a face from a clockwise-rotated canvas back to the source image.
  DetectedFace _restoreRotation(
    DetectedFace face, {
    required double angleRadians,
  }) {
    final double cosine = math.cos(angleRadians);
    final double sine = math.sin(angleRadians);
    final double centerX = (face.imageWidth - 1) / 2;
    final double centerY = (face.imageHeight - 1) / 2;
    FacePoint restorePoint(FacePoint point) {
      final double horizontalOffset = point.x - centerX;
      final double verticalOffset = point.y - centerY;
      return FacePoint(
        x: (cosine * horizontalOffset + sine * verticalOffset + centerX).clamp(0, face.imageWidth.toDouble()).toDouble(),
        y: (-sine * horizontalOffset + cosine * verticalOffset + centerY).clamp(0, face.imageHeight.toDouble()).toDouble(),
      );
    }

    final List<FacePoint> corners = <FacePoint>[
      restorePoint(face.boundingBox.topLeft),
      restorePoint(face.boundingBox.topRight),
      restorePoint(face.boundingBox.bottomRight),
      restorePoint(face.boundingBox.bottomLeft),
    ];
    final double left = corners.map((point) => point.x).reduce(math.min);
    final double top = corners.map((point) => point.y).reduce(math.min);
    final double right = corners.map((point) => point.x).reduce(math.max);
    final double bottom = corners.map((point) => point.y).reduce(math.max);
    final Map<FaceLandmarkType, FaceLandmark> landmarks = <FaceLandmarkType, FaceLandmark>{
      for (final MapEntry<FaceLandmarkType, FaceLandmark> entry in face.landmarks.entries)
        entry.key: FaceLandmark(
          position: restorePoint(entry.value.position),
          confidence: entry.value.confidence,
        ),
    };
    final FacePoint leftEye = landmarks[FaceLandmarkType.leftEye]!.position;
    final FacePoint rightEye = landmarks[FaceLandmarkType.rightEye]!.position;
    final double rollRadians = math.atan2(
      rightEye.y - leftEye.y,
      rightEye.x - leftEye.x,
    );
    return DetectedFace(
      boundingBox: FaceBoundingBox.fromLTRB(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ),
      confidence: face.confidence,
      landmarks: landmarks,
      imageWidth: face.imageWidth,
      imageHeight: face.imageHeight,
      rollDegrees: rollRadians * 180 / math.pi,
    );
  }

  /// Copies public limits into a non-recursive deskew pass.
  FaceDetectorOptions _rotationRecoveryOptions(FaceDetectorOptions options) => FaceDetectorOptions(
    accuracy: FaceDetectionAccuracy.balanced,
    minimumFaceSize: options.minimumFaceSize,
    maximumFaceSize: options.maximumFaceSize,
    confidenceThreshold: math.max(options.confidenceThreshold, 0.75),
    minimumLandmarkConfidence: math.max(
      options.minimumLandmarkConfidence,
      0.35,
    ),
    maximumFaces: options.maximumFaces,
    runInIsolate: false,
    maximumDecodedPixels: options.maximumDecodedPixels,
    enableRotationRecovery: false,
    enableHeuristicFallback: false,
  );

  /// Maps one working-image candidate and its landmarks to source pixels.
  DetectedFace _toDetectedFace({required AnalysisImage image, required _DetectionCandidate candidate}) {
    final double scaleX = image.sourceScaleX;
    final double scaleY = image.sourceScaleY;
    final Map<FaceLandmarkType, FaceLandmark> landmarks = <FaceLandmarkType, FaceLandmark>{
      for (final MapEntry<FaceLandmarkType, _FeaturePoint> entry in candidate.landmarks.entries)
        entry.key: FaceLandmark(
          position: FacePoint(
            x: entry.value.x * scaleX,
            y: entry.value.y * scaleY,
          ),
          confidence: entry.value.confidence,
        ),
    };
    final FacePoint leftEye = landmarks[FaceLandmarkType.leftEye]!.position;
    final FacePoint rightEye = landmarks[FaceLandmarkType.rightEye]!.position;
    final double rollRadians = math.atan2(
      rightEye.y - leftEye.y,
      rightEye.x - leftEye.x,
    );
    return DetectedFace(
      boundingBox: FaceBoundingBox(
        left: candidate.window.left * scaleX,
        top: candidate.window.top * scaleY,
        width: candidate.window.width * scaleX,
        height: candidate.window.height * scaleY,
      ).clamped(imageWidth: image.originalWidth, imageHeight: image.originalHeight),
      confidence: candidate.confidence,
      landmarks: landmarks,
      imageWidth: image.originalWidth,
      imageHeight: image.originalHeight,
      rollDegrees: rollRadians * 180 / math.pi,
    );
  }

  /// Chooses bounded scan parameters for one accuracy setting.
  _ScanProfile _profileFor(FaceDetectionAccuracy accuracy) => switch (accuracy) {
    FaceDetectionAccuracy.fast => const _ScanProfile(
      maximumDimension: 320,
      pyramidFactor: 1.34,
      stepFraction: 0.18,
      aspectRatios: <double>[0.82],
      maximumEvaluatedWindows: 700,
    ),
    FaceDetectionAccuracy.balanced => const _ScanProfile(
      maximumDimension: 480,
      pyramidFactor: 1.22,
      stepFraction: 0.12,
      aspectRatios: <double>[0.78, 0.88],
      maximumEvaluatedWindows: 1800,
    ),
    FaceDetectionAccuracy.accurate => const _ScanProfile(
      maximumDimension: 720,
      pyramidFactor: 1.15,
      stepFraction: 0.08,
      aspectRatios: <double>[0.74, 0.82, 0.90],
      maximumEvaluatedWindows: 5000,
    ),
  };

  /// Rechecks asserted options when assertions are disabled.
  void _validateOptions(FaceDetectorOptions options) {
    if (!options.minimumFaceSize.isFinite || options.minimumFaceSize <= 0 || options.minimumFaceSize > 1) {
      throw ArgumentError.value(options.minimumFaceSize, 'minimumFaceSize', 'Must be finite and in the range (0, 1]');
    }
    if (!options.maximumFaceSize.isFinite || options.maximumFaceSize <= 0 || options.maximumFaceSize > 1 || options.maximumFaceSize < options.minimumFaceSize) {
      throw ArgumentError.value(options.maximumFaceSize, 'maximumFaceSize', 'Must be finite, in range, and not smaller than minimumFaceSize');
    }
    if (!options.confidenceThreshold.isFinite || options.confidenceThreshold < 0 || options.confidenceThreshold > 1) {
      throw ArgumentError.value(options.confidenceThreshold, 'confidenceThreshold', 'Must be finite and between zero and one');
    }
    if (!options.minimumLandmarkConfidence.isFinite || options.minimumLandmarkConfidence < 0 || options.minimumLandmarkConfidence > 1) {
      throw ArgumentError.value(
        options.minimumLandmarkConfidence,
        'minimumLandmarkConfidence',
        'Must be finite and between zero and one',
      );
    }
    if (options.maximumFaces < 1) {
      throw ArgumentError.value(options.maximumFaces, 'maximumFaces', 'Must be positive');
    }
    if (options.maximumDecodedPixels < 1) {
      throw ArgumentError.value(options.maximumDecodedPixels, 'maximumDecodedPixels', 'Must be positive');
    }
  }
}

/// Where landmarks sit inside a face window produced by one detector.
///
/// The cascade and the heuristic scanner frame faces differently, so each
/// carries its own geometry. Every value is a fraction of the window and is
/// mirrored horizontally for the right side, which keeps the two eye searches
/// symmetric by construction.
final class _LandmarkGeometry {
  /// Creates a landmark geometry.
  const _LandmarkGeometry({
    required this.priorStrength,
    required this.eyeOuterFraction,
    required this.eyeInnerFraction,
    required this.eyeTopFraction,
    required this.eyeBottomFraction,
    required this.expectedLeftEyeX,
    required this.expectedEyeY,
    required this.expectedEyeSeparation,
    required this.mouthFollowsEyeMidpoint,
    required this.mouthHalfWidth,
    required this.mouthRadiusXFraction,
    required this.mouthCornerFraction,
    required this.mouthTopFraction,
    required this.mouthBottomFraction,
    required this.expectedMouthY,
    required this.expectedMouthSpacing,
  });

  /// Geometry of a window accepted by the LBP cascade.
  ///
  /// The values come from hand-labelled landmarks on the reference corpus, so
  /// they describe where the cascade actually frames a face rather than where
  /// a face sits in an idealized crop.
  static const _LandmarkGeometry cascade = _LandmarkGeometry(
    priorStrength: 12,
    eyeOuterFraction: 0.09,
    eyeInnerFraction: 0.40,
    eyeTopFraction: 0.10,
    eyeBottomFraction: 0.36,
    expectedLeftEyeX: 0.231,
    expectedEyeY: 0.222,
    expectedEyeSeparation: 0.54,
    mouthFollowsEyeMidpoint: true,
    mouthHalfWidth: 0.06,
    mouthRadiusXFraction: 0.26,
    mouthCornerFraction: 0.20,
    mouthTopFraction: 0.66,
    mouthBottomFraction: 0.96,
    expectedMouthY: 0.81,
    expectedMouthSpacing: 0.59,
  );

  /// Geometry of a window produced by the opt-in heuristic scanner.
  static const _LandmarkGeometry heuristic = _LandmarkGeometry(
    priorStrength: 0.75,
    eyeOuterFraction: 0.12,
    eyeInnerFraction: 0.46,
    eyeTopFraction: 0.27,
    eyeBottomFraction: 0.51,
    expectedLeftEyeX: 0.30,
    expectedEyeY: 0.39,
    expectedEyeSeparation: 0.40,
    mouthFollowsEyeMidpoint: false,
    mouthHalfWidth: 0.26,
    mouthRadiusXFraction: 0.055,
    mouthCornerFraction: 0.12,
    mouthTopFraction: 0.68,
    mouthBottomFraction: 0.88,
    expectedMouthY: 0.77,
    expectedMouthSpacing: 0.38,
  );

  /// How strongly a search is pulled toward its expected position.
  ///
  /// The darkest response in an eye band is often an eyebrow or a shadow
  /// rather than the eye, so weighting the distance to the expected position
  /// heavily keeps a search close to the geometry the face box implies while
  /// still letting it follow a tilted head.
  final double priorStrength;

  /// Outer horizontal edge of the left eye's search band.
  final double eyeOuterFraction;

  /// Inner horizontal edge of the left eye's search band.
  final double eyeInnerFraction;

  /// Upper edge of both eye search bands.
  final double eyeTopFraction;

  /// Lower edge of both eye search bands.
  final double eyeBottomFraction;

  /// Horizontal position the left eye is expected to occupy.
  final double expectedLeftEyeX;

  /// Vertical position both eyes are expected to occupy.
  final double expectedEyeY;

  /// Expected horizontal distance between both eyes.
  final double expectedEyeSeparation;

  /// Whether the mouth band is centered on the eye midpoint.
  ///
  /// The heuristic scanner keeps a fixed, wide band because it uses the
  /// horizontal distance from the eye midpoint to the mouth as a rejection
  /// signal, which a centered band would make meaningless.
  final bool mouthFollowsEyeMidpoint;

  /// Half-width of the mouth search band, as a fraction of the window.
  final double mouthHalfWidth;

  /// Half-width of the mouth integration patch, as a fraction of the window.
  ///
  /// A mouth is a wide, thin dark structure, so integrating over a patch about
  /// as wide as the mouth itself locates the lip line instead of the corner
  /// shadows, which are darker but off-center.
  final double mouthRadiusXFraction;

  /// Base half-width of the mouth, as a fraction of the window.
  final double mouthCornerFraction;

  /// Upper edge of the mouth search band.
  final double mouthTopFraction;

  /// Lower edge of the mouth search band.
  final double mouthBottomFraction;

  /// Vertical position the mouth is expected to occupy.
  final double expectedMouthY;

  /// Expected vertical distance from the eye line to the mouth.
  final double expectedMouthSpacing;
}

/// Parameters that control the amount of multi-scale scanning.
final class _ScanProfile {
  /// Creates a fixed scan profile.
  const _ScanProfile({
    required this.maximumDimension,
    required this.pyramidFactor,
    required this.stepFraction,
    required this.aspectRatios,
    required this.maximumEvaluatedWindows,
  });

  /// Longest working-image edge.
  final int maximumDimension;

  /// Multiplicative step between successive face sizes.
  final double pyramidFactor;

  /// Scan movement as a fraction of the current window size.
  final double stepFraction;

  /// Candidate width-to-height ratios.
  final List<double> aspectRatios;

  /// Maximum number of promising windows receiving landmark searches.
  final int maximumEvaluatedWindows;
}

/// Integer face-shaped window in the working image.
final class _ScanWindow {
  /// Creates a scan window.
  const _ScanWindow({required this.left, required this.top, required this.width, required this.height});

  /// Left edge in working pixels.
  final int left;

  /// Top edge in working pixels.
  final int top;

  /// Width in working pixels.
  final int width;

  /// Height in working pixels.
  final int height;

  /// Right half-open edge in working pixels.
  int get right => left + width;

  /// Bottom half-open edge in working pixels.
  int get bottom => top + height;

  /// Area in working pixels.
  double get area => (width * height).toDouble();

  /// Returns the intersection area with [other].
  double intersectionArea(_ScanWindow other) {
    final int intersectionWidth = math.max(0, math.min(right, other.right) - math.max(left, other.left));
    final int intersectionHeight = math.max(0, math.min(bottom, other.bottom) - math.max(top, other.top));
    return (intersectionWidth * intersectionHeight).toDouble();
  }
}

/// Preliminary score and reusable statistics for one scan window.
final class _WindowScore {
  /// Creates a preliminary score.
  const _WindowScore({
    required this.window,
    required this.score,
    required this.standardDeviation,
    required this.eyeContrast,
    required this.mouthScore,
  });

  /// Scored scan window.
  final _ScanWindow window;

  /// Coarse face likelihood.
  final double score;

  /// Luminance standard deviation within the window.
  final double standardDeviation;

  /// Coarse eye-band contrast retained for diagnostics and weighting.
  final double eyeContrast;

  /// Coarse mouth response used to size mouth landmarks.
  final double mouthScore;
}

/// Internal point response used before source-image scaling.
final class _FeaturePoint {
  /// Creates a feature point.
  const _FeaturePoint({required this.x, required this.y, required this.confidence});

  /// Horizontal coordinate in working pixels.
  final double x;

  /// Vertical coordinate in working pixels.
  final double y;

  /// Local response normalized to zero through one.
  final double confidence;
}

/// A fully evaluated window ready for overlap suppression.
final class _DetectionCandidate {
  /// Creates a candidate with sparse [landmarks].
  const _DetectionCandidate({
    required this.window,
    required this.confidence,
    required this.landmarkConfidence,
    required this.landmarks,
  });

  /// Face-shaped scan window.
  final _ScanWindow window;

  /// Combined structure and landmark confidence.
  final double confidence;

  /// Mean confidence across the six sparse feature estimates.
  final double landmarkConfidence;

  /// Landmark responses in working-image coordinates.
  final Map<FaceLandmarkType, _FeaturePoint> landmarks;
}

/// One source-space face produced by either the primary or a recovery pass.
final class _FaceProposal {
  /// Creates a face proposal with its pass provenance.
  const _FaceProposal({required this.face, required this.isRecovery});

  /// Source-space face returned by one cascade pass.
  final DetectedFace face;

  /// Whether the face came from a rotated lower-resolution pass.
  final bool isRecovery;

  /// Ordering score that favors reliable landmarks within one pass type.
  double get quality => face.confidence * 0.8 + face.landmarkConfidence * 0.2;
}
