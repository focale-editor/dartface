import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartface/src/image/integral_plane.dart';

/// A bounded-resolution set of color planes used by the detector.
///
/// Only luminance is derived while the working image is built. The color
/// planes and every summed-area plane are built on first use, because a scan
/// that finds no face never needs them and the opt-in heuristic detector is
/// the only consumer of the skin and red-chroma statistics.
final class AnalysisImage {
  /// Downsamples owned RGBA [bytes] to a working image bounded by
  /// [maximumDimension] and derives its luminance plane.
  factory AnalysisImage.fromRgba({
    required Uint8List bytes,
    required int width,
    required int height,
    required int maximumDimension,
  }) {
    if (bytes.length != width * height * 4) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Expected ${width * height * 4} RGBA bytes');
    }
    final double reduction = math.min(1, maximumDimension / math.max(width, height));
    final int analysisWidth = math.max(1, (width * reduction).round());
    final int analysisHeight = math.max(1, (height * reduction).round());
    final double sourcePerAnalysisX = width / analysisWidth;
    final double sourcePerAnalysisY = height / analysisHeight;
    final int pixelCount = analysisWidth * analysisHeight;
    final Uint8List samples = Uint8List(pixelCount * 4);
    final Float64List luminance = Float64List(pixelCount);

    for (int y = 0; y < analysisHeight; y++) {
      final int sourceY = math.min(height - 1, ((y + 0.5) * sourcePerAnalysisY).floor());
      final int sourceRow = sourceY * width;
      int destinationOffset = y * analysisWidth;
      for (int x = 0; x < analysisWidth; x++) {
        final int sourceX = math.min(width - 1, ((x + 0.5) * sourcePerAnalysisX).floor());
        final int sourceOffset = (sourceRow + sourceX) * 4;
        final int sampleOffset = destinationOffset * 4;
        samples[sampleOffset] = bytes[sourceOffset];
        samples[sampleOffset + 1] = bytes[sourceOffset + 1];
        samples[sampleOffset + 2] = bytes[sourceOffset + 2];
        samples[sampleOffset + 3] = bytes[sourceOffset + 3];
        final double opacity = bytes[sourceOffset + 3] / 255;
        final double red = bytes[sourceOffset] * opacity + 240 * (1 - opacity);
        final double green = bytes[sourceOffset + 1] * opacity + 240 * (1 - opacity);
        final double blue = bytes[sourceOffset + 2] * opacity + 240 * (1 - opacity);
        luminance[destinationOffset] = 0.299 * red + 0.587 * green + 0.114 * blue;
        destinationOffset++;
      }
    }

    return AnalysisImage._(
      originalWidth: width,
      originalHeight: height,
      width: analysisWidth,
      height: analysisHeight,
      samples: samples,
      luminance: luminance,
    );
  }

  /// Builds a rotated working image directly from source-resolution pixels.
  ///
  /// Sampling the source once retains more cascade detail than rotating an
  /// already reduced image. Positive angles rotate the visible image clockwise.
  factory AnalysisImage.fromRotatedRgba({
    required Uint8List bytes,
    required int width,
    required int height,
    required int maximumDimension,
    required double angleRadians,
  }) {
    if (bytes.length != width * height * 4) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Expected ${width * height * 4} RGBA bytes',
      );
    }
    if (!angleRadians.isFinite) {
      throw ArgumentError.value(
        angleRadians,
        'angleRadians',
        'Must be finite',
      );
    }
    final double reduction = math.min(
      1,
      maximumDimension / math.max(width, height),
    );
    final int analysisWidth = math.max(1, (width * reduction).round());
    final int analysisHeight = math.max(1, (height * reduction).round());
    final double sourcePerAnalysisX = width / analysisWidth;
    final double sourcePerAnalysisY = height / analysisHeight;
    final double sourceCenterX = (width - 1) / 2;
    final double sourceCenterY = (height - 1) / 2;
    final double cosine = math.cos(angleRadians);
    final double sine = math.sin(angleRadians);
    final Uint8List samples = Uint8List(analysisWidth * analysisHeight * 4);
    final Float64List luminance = Float64List(
      analysisWidth * analysisHeight,
    );

    for (int y = 0; y < analysisHeight; y++) {
      final double destinationY = (y + 0.5) * sourcePerAnalysisY - 0.5;
      final double verticalOffset = destinationY - sourceCenterY;
      for (int x = 0; x < analysisWidth; x++) {
        final double destinationX = (x + 0.5) * sourcePerAnalysisX - 0.5;
        final double horizontalOffset = destinationX - sourceCenterX;
        final double sourceX = cosine * horizontalOffset + sine * verticalOffset + sourceCenterX;
        final double sourceY = -sine * horizontalOffset + cosine * verticalOffset + sourceCenterY;
        final int destinationPixel = y * analysisWidth + x;
        final int destinationOffset = destinationPixel * 4;
        if (sourceX < 0 || sourceX > width - 1 || sourceY < 0 || sourceY > height - 1) {
          samples[destinationOffset] = 240;
          samples[destinationOffset + 1] = 240;
          samples[destinationOffset + 2] = 240;
          samples[destinationOffset + 3] = 255;
          luminance[destinationPixel] = 240;
          continue;
        }

        final int left = sourceX.floor();
        final int top = sourceY.floor();
        final int right = math.min(width - 1, left + 1);
        final int bottom = math.min(height - 1, top + 1);
        final double horizontalWeight = sourceX - left;
        final double verticalWeight = sourceY - top;
        final int topLeftOffset = (top * width + left) * 4;
        final int topRightOffset = (top * width + right) * 4;
        final int bottomLeftOffset = (bottom * width + left) * 4;
        final int bottomRightOffset = (bottom * width + right) * 4;
        for (int channel = 0; channel < 4; channel++) {
          final double topValue = bytes[topLeftOffset + channel] * (1 - horizontalWeight) + bytes[topRightOffset + channel] * horizontalWeight;
          final double bottomValue = bytes[bottomLeftOffset + channel] * (1 - horizontalWeight) + bytes[bottomRightOffset + channel] * horizontalWeight;
          samples[destinationOffset + channel] = (topValue * (1 - verticalWeight) + bottomValue * verticalWeight).round().clamp(0, 255);
        }
        luminance[destinationPixel] = _compositedLuminance(
          samples,
          destinationOffset,
        );
      }
    }

    return AnalysisImage._(
      originalWidth: width,
      originalHeight: height,
      width: analysisWidth,
      height: analysisHeight,
      samples: samples,
      luminance: luminance,
    );
  }

  /// Creates an analysis image from its sampled pixels and luminance plane.
  AnalysisImage._({
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
    required this._samples,
    required this.luminance,
  });

  /// Width of the caller's image.
  final int originalWidth;

  /// Height of the caller's image.
  final int originalHeight;

  /// Width of the bounded working image.
  final int width;

  /// Height of the bounded working image.
  final int height;

  /// Row-major straight-alpha RGBA samples of the working image.
  final Uint8List _samples;

  /// Row-major luminance values from zero to 255.
  final Float64List luminance;

  /// Row-major skin-color likelihoods from zero to one.
  late final Float64List skin = _buildSkin();

  /// Row-major red-chroma strengths from zero to one.
  late final Float64List redness = _buildRedness();

  /// Mean RGB channel spread, normalized to zero through one.
  late final double colorfulness = _buildColorfulness();

  /// Summed luminance values.
  late final IntegralPlane luminanceIntegral = IntegralPlane.fromSamples(samples: luminance, width: width, height: height);

  /// Summed squared luminance values.
  late final IntegralPlane squaredLuminanceIntegral = IntegralPlane.fromSamples(samples: luminance, width: width, height: height, squareSamples: true);

  /// Summed skin-color likelihoods.
  late final IntegralPlane skinIntegral = IntegralPlane.fromSamples(samples: skin, width: width, height: height);

  /// Summed red-chroma strengths.
  late final IntegralPlane rednessIntegral = IntegralPlane.fromSamples(samples: redness, width: width, height: height);

  /// Source pixels represented by one working pixel on the horizontal axis.
  double get sourceScaleX => originalWidth / width;

  /// Source pixels represented by one working pixel on the vertical axis.
  double get sourceScaleY => originalHeight / height;

  /// Reads one luminance sample without allocating a color object.
  double luminanceAt(int x, int y) => luminance[y * width + x];

  /// Reads one red-chroma sample without allocating a color object.
  double rednessAt(int x, int y) => redness[y * width + x];

  /// Measures skin-color likelihood on every working pixel.
  Float64List _buildSkin() {
    final int pixelCount = width * height;
    final Float64List plane = Float64List(pixelCount);
    for (int index = 0; index < pixelCount; index++) {
      final int offset = index * 4;
      final int alpha = _samples[offset + 3];
      if (alpha < 32) {
        continue;
      }
      final double opacity = alpha / 255;
      final double ground = 240 * (1 - opacity);
      plane[index] = _skinLikelihood(
        red: _samples[offset] * opacity + ground,
        green: _samples[offset + 1] * opacity + ground,
        blue: _samples[offset + 2] * opacity + ground,
      );
    }
    return plane;
  }

  /// Measures how strongly red dominates the other channels on every pixel.
  Float64List _buildRedness() {
    final int pixelCount = width * height;
    final Float64List plane = Float64List(pixelCount);
    for (int index = 0; index < pixelCount; index++) {
      final int offset = index * 4;
      final double opacity = _samples[offset + 3] / 255;
      final double ground = 240 * (1 - opacity);
      final double red = _samples[offset] * opacity + ground;
      final double green = _samples[offset + 1] * opacity + ground;
      final double blue = _samples[offset + 2] * opacity + ground;
      plane[index] = ((red - (green + blue) / 2) / 110).clamp(0, 1);
    }
    return plane;
  }

  /// Averages the composited RGB channel spread across the working image.
  double _buildColorfulness() {
    final int pixelCount = width * height;
    double sum = 0;
    for (int index = 0; index < pixelCount; index++) {
      final int offset = index * 4;
      final double opacity = _samples[offset + 3] / 255;
      final double ground = 240 * (1 - opacity);
      final double red = _samples[offset] * opacity + ground;
      final double green = _samples[offset + 1] * opacity + ground;
      final double blue = _samples[offset + 2] * opacity + ground;
      sum += (math.max(red, math.max(green, blue)) - math.min(red, math.min(green, blue))) / 255;
    }
    return sum / pixelCount;
  }

  /// Estimates how closely an RGB triplet follows common human-skin chroma.
  static double _skinLikelihood({required double red, required double green, required double blue}) {
    final double luminance = 0.299 * red + 0.587 * green + 0.114 * blue;
    if (luminance < 16 || luminance > 252) {
      return 0;
    }
    final double chromaBlue = 128 - 0.168736 * red - 0.331264 * green + 0.5 * blue;
    final double chromaRed = 128 + 0.5 * red - 0.418688 * green - 0.081312 * blue;
    final double blueDistance = (chromaBlue - 109) / 38;
    final double redDistance = (chromaRed - 152) / 34;
    final double ellipseDistance = math.sqrt(blueDistance * blueDistance + redDistance * redDistance);
    final double chromaScore = (1.25 - ellipseDistance).clamp(0, 1);
    final double total = math.max(1, red + green + blue);
    final double normalizedRed = red / total;
    final double normalizedGreen = green / total;
    final double ratioScore = (1 - (normalizedRed - 0.43).abs() / 0.18).clamp(0, 1) * (1 - (normalizedGreen - 0.32).abs() / 0.16).clamp(0, 1);
    final double warmthScore = ((red - blue + 24) / 75).clamp(0, 1);
    final double darknessAllowance = (luminance / 42).clamp(0.35, 1);
    return (0.62 * chromaScore + 0.23 * ratioScore + 0.15 * warmthScore) * darknessAllowance;
  }

  /// Returns luminance after compositing one straight-alpha sample on gray.
  static double _compositedLuminance(Uint8List samples, int offset) {
    final double opacity = samples[offset + 3] / 255;
    final double ground = 240 * (1 - opacity);
    final double red = samples[offset] * opacity + ground;
    final double green = samples[offset + 1] * opacity + ground;
    final double blue = samples[offset + 2] * opacity + ground;
    return 0.299 * red + 0.587 * green + 0.114 * blue;
  }
}
