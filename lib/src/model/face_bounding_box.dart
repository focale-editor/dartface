import 'dart:math' as math;

import 'package:dartface/src/model/face_point.dart';

/// An axis-aligned rectangle expressed in source-image pixels.
final class FaceBoundingBox {
  /// Creates a rectangle from its top-left corner and size.
  const FaceBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(width >= 0, 'width must not be negative'),
       assert(height >= 0, 'height must not be negative');

  /// Creates a rectangle from its four edges.
  factory FaceBoundingBox.fromLTRB({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    if (right < left) {
      throw ArgumentError.value(right, 'right', 'Must be greater than or equal to left');
    }
    if (bottom < top) {
      throw ArgumentError.value(bottom, 'bottom', 'Must be greater than or equal to top');
    }
    return FaceBoundingBox(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// Horizontal coordinate of the left edge.
  final double left;

  /// Vertical coordinate of the top edge.
  final double top;

  /// Rectangle width in pixels.
  final double width;

  /// Rectangle height in pixels.
  final double height;

  /// Horizontal coordinate of the right edge.
  double get right => left + width;

  /// Vertical coordinate of the bottom edge.
  double get bottom => top + height;

  /// Area in square pixels.
  double get area => width * height;

  /// Center of the rectangle.
  FacePoint get center => FacePoint(x: left + width / 2, y: top + height / 2);

  /// Top-left corner of the rectangle.
  FacePoint get topLeft => FacePoint(x: left, y: top);

  /// Top-right corner of the rectangle.
  FacePoint get topRight => FacePoint(x: right, y: top);

  /// Bottom-right corner of the rectangle.
  FacePoint get bottomRight => FacePoint(x: right, y: bottom);

  /// Bottom-left corner of the rectangle.
  FacePoint get bottomLeft => FacePoint(x: left, y: bottom);

  /// Corners ordered clockwise from [topLeft].
  List<FacePoint> get corners => List<FacePoint>.unmodifiable(<FacePoint>[
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ]);

  /// Returns the fraction of overlap between this box and [other].
  double intersectionOverUnion(FaceBoundingBox other) {
    final double intersectionLeft = math.max(left, other.left);
    final double intersectionTop = math.max(top, other.top);
    final double intersectionRight = math.min(right, other.right);
    final double intersectionBottom = math.min(bottom, other.bottom);
    final double intersectionWidth = math.max(0, intersectionRight - intersectionLeft);
    final double intersectionHeight = math.max(0, intersectionBottom - intersectionTop);
    final double intersectionArea = intersectionWidth * intersectionHeight;
    final double unionArea = area + other.area - intersectionArea;
    return unionArea == 0 ? 0 : intersectionArea / unionArea;
  }

  /// Keeps every edge inside an image of [imageWidth] by [imageHeight].
  FaceBoundingBox clamped({
    required int imageWidth,
    required int imageHeight,
  }) {
    final double clampedLeft = left.clamp(0, imageWidth).toDouble();
    final double clampedTop = top.clamp(0, imageHeight).toDouble();
    final double clampedRight = right.clamp(clampedLeft, imageWidth).toDouble();
    final double clampedBottom = bottom.clamp(clampedTop, imageHeight).toDouble();
    return FaceBoundingBox.fromLTRB(
      left: clampedLeft,
      top: clampedTop,
      right: clampedRight,
      bottom: clampedBottom,
    );
  }

  @override
  bool operator ==(Object other) => other is FaceBoundingBox && left == other.left && top == other.top && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'FaceBoundingBox(left: $left, top: $top, width: $width, height: $height)';
}
