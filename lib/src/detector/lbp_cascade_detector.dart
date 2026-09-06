import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartface/src/detector/generated/lbp_frontal_face_cascade.dart';
import 'package:dartface/src/image/analysis_image.dart';
import 'package:dartface/src/image/integral_plane.dart';
import 'package:dartface/src/model/face_detector_options.dart';

/// Runs a boosted local-binary-pattern cascade with a pure Dart evaluator.
final class LbpCascadeDetector {
  /// Creates a stateless cascade detector.
  const LbpCascadeDetector();

  /// Searches [image] at multiple scales and groups neighboring passes.
  List<LbpDetection> detect({
    required AnalysisImage image,
    required FaceDetectorOptions options,
  }) {
    final _LbpScanProfile profile = _profileFor(options.accuracy);
    final int shortestEdge = math.min(image.width, image.height);
    final int minimumSize = math.max(lbpCascadeHeight, (shortestEdge * options.minimumFaceSize).round());
    final int maximumSize = math.min(shortestEdge, (shortestEdge * options.maximumFaceSize).round());
    if (minimumSize > maximumSize) {
      return const <LbpDetection>[];
    }

    final List<_RawLbpDetection> rawDetections = <_RawLbpDetection>[];
    double pyramidScale = 1;
    while (lbpCascadeHeight * pyramidScale < minimumSize) {
      pyramidScale *= profile.scaleFactor;
    }
    while (lbpCascadeHeight * pyramidScale <= maximumSize + 0.5) {
      final _LuminancePyramidLevel? level = _LuminancePyramidLevel.fromImage(image: image, scale: pyramidScale);
      pyramidScale *= profile.scaleFactor;
      if (level == null) {
        continue;
      }
      // Rounding the resized dimensions moves a level slightly away from the
      // requested scale, so windows are mapped back with the scale the level
      // actually has instead of the one that was asked for.
      final double levelScaleX = image.width / level.width;
      final double levelScaleY = image.height / level.height;
      for (int top = 0; top <= level.height - lbpCascadeHeight; top += profile.windowStep) {
        for (int left = 0; left <= level.width - lbpCascadeWidth; left += profile.windowStep) {
          final double? quality = _evaluateWindow(
            integral: level.integral,
            left: left,
            top: top,
          );
          if (quality != null) {
            rawDetections.add(
              _RawLbpDetection(
                left: left * levelScaleX,
                top: top * levelScaleY,
                width: lbpCascadeWidth * levelScaleX,
                height: lbpCascadeHeight * levelScaleY,
                quality: quality,
              ),
            );
          }
        }
      }
    }
    return _groupDetections(rawDetections: rawDetections, minimumNeighbors: profile.minimumNeighbors);
  }

  /// Evaluates all cascade stages and returns their mean positive margin.
  double? _evaluateWindow({
    required IntegralPlane integral,
    required int left,
    required int top,
  }) {
    final int stageCount = lbpStageWeakCounts.length;
    int weakIndex = 0;
    double normalizedMarginSum = 0;
    for (int stageIndex = 0; stageIndex < stageCount; stageIndex++) {
      final int weakCount = lbpStageWeakCounts[stageIndex];
      double stageSum = 0;
      for (int indexWithinStage = 0; indexWithinStage < weakCount; indexWithinStage++) {
        final int rectangleOffset = lbpWeakFeatureIndexes[weakIndex] * 4;
        final int category = integral.localBinaryPattern(
          left: left + lbpFeatureRectangles[rectangleOffset],
          top: top + lbpFeatureRectangles[rectangleOffset + 1],
          cellWidth: lbpFeatureRectangles[rectangleOffset + 2],
          cellHeight: lbpFeatureRectangles[rectangleOffset + 3],
        );
        final int categoryMask = lbpWeakCategoryMasks[weakIndex * 8 + (category >> 5)];
        final bool belongsToSubset = categoryMask & (1 << (category & 31)) != 0;
        stageSum += belongsToSubset ? lbpWeakLeftValues[weakIndex] : lbpWeakRightValues[weakIndex];
        weakIndex++;
      }
      final double margin = stageSum - lbpStageThresholds[stageIndex];
      if (margin < 0) {
        return null;
      }
      normalizedMarginSum += (margin / weakCount).clamp(0, 1);
    }
    return normalizedMarginSum / stageCount;
  }

  /// Groups neighboring positive windows and removes unsupported single hits.
  List<LbpDetection> _groupDetections({required List<_RawLbpDetection> rawDetections, required int minimumNeighbors}) {
    if (rawDetections.isEmpty) {
      return const <LbpDetection>[];
    }
    final List<int> parents = <int>[for (int index = 0; index < rawDetections.length; index++) index];
    final List<int> spatialOrder =
        <int>[
          for (int index = 0; index < rawDetections.length; index++) index,
        ]..sort(
          (first, second) => rawDetections[first].left.compareTo(
            rawDetections[second].left,
          ),
        );
    for (int firstPosition = 0; firstPosition < spatialOrder.length; firstPosition++) {
      final int firstIndex = spatialOrder[firstPosition];
      final _RawLbpDetection first = rawDetections[firstIndex];
      final double maximumHorizontalDistance = first.size * 0.24;
      for (int secondPosition = firstPosition + 1; secondPosition < spatialOrder.length; secondPosition++) {
        final int secondIndex = spatialOrder[secondPosition];
        final _RawLbpDetection second = rawDetections[secondIndex];
        if (second.left - first.left > maximumHorizontalDistance) {
          break;
        }
        if ((second.top - first.top).abs() <= maximumHorizontalDistance && _areNeighbors(first, second)) {
          _union(parents, firstIndex, secondIndex);
        }
      }
    }

    final Map<int, List<_RawLbpDetection>> groups = <int, List<_RawLbpDetection>>{};
    for (int index = 0; index < rawDetections.length; index++) {
      groups.putIfAbsent(_root(parents, index), () => <_RawLbpDetection>[]).add(rawDetections[index]);
    }
    final List<LbpDetection> grouped = <LbpDetection>[];
    for (final List<_RawLbpDetection> group in groups.values) {
      if (group.length < minimumNeighbors) {
        continue;
      }
      double totalWeight = 0;
      double leftSum = 0;
      double topSum = 0;
      double widthSum = 0;
      double heightSum = 0;
      double qualitySum = 0;
      for (final _RawLbpDetection detection in group) {
        final double weight = 1 + detection.quality;
        totalWeight += weight;
        leftSum += detection.left * weight;
        topSum += detection.top * weight;
        widthSum += detection.width * weight;
        heightSum += detection.height * weight;
        qualitySum += detection.quality;
      }
      final double supportScore = 1 - math.exp(-group.length / 3.2);
      final double confidence = (0.48 + supportScore * 0.34 + qualitySum / group.length * 0.30).clamp(0, 0.99);
      grouped.add(
        LbpDetection(
          left: leftSum / totalWeight,
          top: topSum / totalWeight,
          width: widthSum / totalWeight,
          height: heightSum / totalWeight,
          confidence: confidence,
          neighborCount: group.length,
        ),
      );
    }
    grouped.sort((first, second) => second.confidence.compareTo(first.confidence));
    final List<LbpDetection> selected = <LbpDetection>[];
    for (final LbpDetection candidate in grouped) {
      if (selected.every((existing) => candidate.intersectionOverUnion(existing) < 0.34)) {
        selected.add(candidate);
      }
    }
    return selected;
  }

  /// Returns whether two raw windows should contribute to one cluster.
  bool _areNeighbors(_RawLbpDetection first, _RawLbpDetection second) {
    final double smallerSize = math.min(first.size, second.size);
    final double largerSize = math.max(first.size, second.size);
    if (largerSize / smallerSize > 1.38) {
      return false;
    }
    final double tolerance = smallerSize * 0.24;
    return (first.left - second.left).abs() <= tolerance && (first.top - second.top).abs() <= tolerance;
  }

  /// Finds the representative element of one disjoint-set entry.
  int _root(List<int> parents, int index) {
    int current = index;
    while (parents[current] != current) {
      parents[current] = parents[parents[current]];
      current = parents[current];
    }
    return current;
  }

  /// Joins the sets containing [first] and [second].
  void _union(List<int> parents, int first, int second) {
    final int firstRoot = _root(parents, first);
    final int secondRoot = _root(parents, second);
    if (firstRoot != secondRoot) {
      parents[secondRoot] = firstRoot;
    }
  }

  /// Chooses pyramid density and cluster support for one accuracy setting.
  _LbpScanProfile _profileFor(FaceDetectionAccuracy accuracy) => switch (accuracy) {
    FaceDetectionAccuracy.fast => const _LbpScanProfile(scaleFactor: 1.20, windowStep: 2, minimumNeighbors: 2),
    FaceDetectionAccuracy.balanced => const _LbpScanProfile(scaleFactor: 1.12, windowStep: 1, minimumNeighbors: 3),
    FaceDetectionAccuracy.accurate => const _LbpScanProfile(scaleFactor: 1.10, windowStep: 1, minimumNeighbors: 4),
  };
}

/// One grouped cascade detection in working-image coordinates.
final class LbpDetection {
  /// Creates a grouped square detection.
  const LbpDetection({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.confidence,
    required this.neighborCount,
  });

  /// Left edge in working pixels.
  final double left;

  /// Top edge in working pixels.
  final double top;

  /// Width in working pixels.
  final double width;

  /// Height in working pixels.
  final double height;

  /// Confidence derived from support and stage margins.
  final double confidence;

  /// Number of neighboring positive windows in this group.
  final int neighborCount;

  /// Computes overlap with [other] for final duplicate suppression.
  double intersectionOverUnion(LbpDetection other) {
    final double intersectionWidth = math.max(0, math.min(left + width, other.left + other.width) - math.max(left, other.left));
    final double intersectionHeight = math.max(0, math.min(top + height, other.top + other.height) - math.max(top, other.top));
    final double intersection = intersectionWidth * intersectionHeight;
    final double union = width * height + other.width * other.height - intersection;
    return union == 0 ? 0 : intersection / union;
  }
}

/// A single scale-and-position pass before spatial grouping.
final class _RawLbpDetection {
  /// Creates a positive raw cascade response.
  const _RawLbpDetection({required this.left, required this.top, required this.width, required this.height, required this.quality});

  /// Left edge in working pixels.
  final double left;

  /// Top edge in working pixels.
  final double top;

  /// Width in working pixels.
  final double width;

  /// Height in working pixels.
  final double height;

  /// Mean normalized positive margin across stages.
  final double quality;

  /// Mean side length used to compare two windows.
  double get size => (width + height) / 2;
}

/// Search settings used by one public accuracy preset.
final class _LbpScanProfile {
  /// Creates a cascade scan profile.
  const _LbpScanProfile({required this.scaleFactor, required this.windowStep, required this.minimumNeighbors});

  /// Size multiplier between adjacent pyramid levels.
  final double scaleFactor;

  /// Spatial scan step in pixels of the current pyramid level.
  final int windowStep;

  /// Minimum clustered positives required for a detection.
  final int minimumNeighbors;
}

/// One resized luminance level and its rectangular-statistics buffers.
final class _LuminancePyramidLevel {
  /// Resamples [image] using bilinear interpolation at inverse [scale].
  ///
  /// Returns `null` when the resized level would be smaller than the cascade
  /// window, because upsizing it would fabricate pixels and break the mapping
  /// from level coordinates back to working-image coordinates.
  static _LuminancePyramidLevel? fromImage({required AnalysisImage image, required double scale}) {
    final int width = (image.width / scale).round();
    final int height = (image.height / scale).round();
    if (width < lbpCascadeWidth || height < lbpCascadeHeight) {
      return null;
    }
    final Float64List samples = Float64List(width * height);
    final double sourceScaleX = image.width / width;
    final double sourceScaleY = image.height / height;
    // The horizontal taps repeat on every row, so they are resolved once.
    final Int32List leftColumns = Int32List(width);
    final Int32List rightColumns = Int32List(width);
    final Float64List horizontalWeights = Float64List(width);
    for (int x = 0; x < width; x++) {
      final double sourceX = (x + 0.5) * sourceScaleX - 0.5;
      final int left = sourceX.floor().clamp(0, image.width - 1);
      leftColumns[x] = left;
      rightColumns[x] = math.min(image.width - 1, left + 1);
      horizontalWeights[x] = (sourceX - left).clamp(0, 1);
    }
    final Float64List luminance = image.luminance;
    for (int y = 0; y < height; y++) {
      final double sourceY = (y + 0.5) * sourceScaleY - 0.5;
      final int top = sourceY.floor().clamp(0, image.height - 1);
      final int bottom = math.min(image.height - 1, top + 1);
      final double verticalWeight = (sourceY - top).clamp(0, 1);
      final int topRow = top * image.width;
      final int bottomRow = bottom * image.width;
      final int destinationRow = y * width;
      for (int x = 0; x < width; x++) {
        final int left = leftColumns[x];
        final int right = rightColumns[x];
        final double horizontalWeight = horizontalWeights[x];
        final double topValue = luminance[topRow + left] * (1 - horizontalWeight) + luminance[topRow + right] * horizontalWeight;
        final double bottomValue = luminance[bottomRow + left] * (1 - horizontalWeight) + luminance[bottomRow + right] * horizontalWeight;
        samples[destinationRow + x] = topValue * (1 - verticalWeight) + bottomValue * verticalWeight;
      }
    }
    return _LuminancePyramidLevel._(
      width: width,
      height: height,
      integral: IntegralPlane.fromSamples(samples: samples, width: width, height: height),
    );
  }

  /// Creates a level from completed integral planes.
  const _LuminancePyramidLevel._({required this.width, required this.height, required this.integral});

  /// Resized width in pixels.
  final int width;

  /// Resized height in pixels.
  final int height;

  /// Summed luminance values.
  final IntegralPlane integral;
}
