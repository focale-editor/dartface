import 'dart:typed_data';

/// Stores summed-area values for constant-time rectangular statistics.
final class IntegralPlane {
  /// Builds an integral plane from row-major [samples].
  factory IntegralPlane.fromSamples({
    required Float64List samples,
    required int width,
    required int height,
    bool squareSamples = false,
  }) {
    if (samples.length != width * height) {
      throw ArgumentError.value(samples.length, 'samples', 'Expected ${width * height} values');
    }
    final int stride = width + 1;
    final Float64List sums = Float64List(stride * (height + 1));
    for (int y = 0; y < height; y++) {
      double rowSum = 0;
      final int sourceRow = y * width;
      final int destinationRow = (y + 1) * stride;
      final int previousRow = y * stride;
      for (int x = 0; x < width; x++) {
        final double value = samples[sourceRow + x];
        rowSum += squareSamples ? value * value : value;
        sums[destinationRow + x + 1] = sums[previousRow + x + 1] + rowSum;
      }
    }
    return IntegralPlane._(width: width, height: height, sums: sums);
  }

  /// Creates a plane around precomputed [_sums].
  const IntegralPlane._({
    required this.width,
    required this.height,
    required this._sums,
  });

  /// Width of the source sample plane.
  final int width;

  /// Height of the source sample plane.
  final int height;

  /// Integral values with a zero border at the top and left.
  final Float64List _sums;

  /// Row length of the bordered integral buffer.
  int get _stride => width + 1;

  /// Returns the sum inside the half-open rectangle.
  double sum({
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    assert(left >= 0 && left <= right && right <= width, 'Horizontal bounds must be valid');
    assert(top >= 0 && top <= bottom && bottom <= height, 'Vertical bounds must be valid');
    final int stride = _stride;
    final int topRow = top * stride;
    final int bottomRow = bottom * stride;
    return _sums[bottomRow + right] - _sums[topRow + right] - _sums[bottomRow + left] + _sums[topRow + left];
  }

  /// Returns the arithmetic mean inside a non-empty half-open rectangle.
  double mean({
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final int area = (right - left) * (bottom - top);
    if (area <= 0) {
      throw ArgumentError('Integral-plane rectangles must have a positive area');
    }
    return sum(left: left, top: top, right: right, bottom: bottom) / area;
  }

  /// Returns the eight-neighbor local-binary-pattern code of a three-by-three
  /// grid of [cellWidth] by [cellHeight] cells anchored at [left], [top].
  ///
  /// Each surrounding cell contributes one bit when its sum reaches the center
  /// cell's sum. Bits run clockwise from the top-left cell, matching the
  /// ordering used by OpenCV's LBP cascade evaluator. The whole grid is read
  /// from sixteen corner values instead of nine independent rectangle sums,
  /// which keeps the innermost cascade loop free of redundant lookups.
  int localBinaryPattern({
    required int left,
    required int top,
    required int cellWidth,
    required int cellHeight,
  }) {
    assert(left >= 0 && left + 3 * cellWidth <= width, 'The cell grid must stay inside the plane');
    assert(top >= 0 && top + 3 * cellHeight <= height, 'The cell grid must stay inside the plane');
    final Float64List sums = _sums;
    final int stride = _stride;
    final int rowStep = cellHeight * stride;
    final int column0 = left;
    final int column1 = column0 + cellWidth;
    final int column2 = column1 + cellWidth;
    final int column3 = column2 + cellWidth;

    int row = top * stride;
    final double corner00 = sums[row + column0];
    final double corner01 = sums[row + column1];
    final double corner02 = sums[row + column2];
    final double corner03 = sums[row + column3];
    row += rowStep;
    final double corner10 = sums[row + column0];
    final double corner11 = sums[row + column1];
    final double corner12 = sums[row + column2];
    final double corner13 = sums[row + column3];
    row += rowStep;
    final double corner20 = sums[row + column0];
    final double corner21 = sums[row + column1];
    final double corner22 = sums[row + column2];
    final double corner23 = sums[row + column3];
    row += rowStep;
    final double corner30 = sums[row + column0];
    final double corner31 = sums[row + column1];
    final double corner32 = sums[row + column2];
    final double corner33 = sums[row + column3];

    final double center = corner22 - corner12 - corner21 + corner11;
    return (corner11 - corner01 - corner10 + corner00 >= center ? 128 : 0) |
        (corner12 - corner02 - corner11 + corner01 >= center ? 64 : 0) |
        (corner13 - corner03 - corner12 + corner02 >= center ? 32 : 0) |
        (corner23 - corner13 - corner22 + corner12 >= center ? 16 : 0) |
        (corner33 - corner23 - corner32 + corner22 >= center ? 8 : 0) |
        (corner32 - corner22 - corner31 + corner21 >= center ? 4 : 0) |
        (corner31 - corner21 - corner30 + corner20 >= center ? 2 : 0) |
        (corner21 - corner11 - corner20 + corner10 >= center ? 1 : 0);
  }
}
