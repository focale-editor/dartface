/// A two-dimensional point expressed in source-image pixels.
final class FacePoint {
  /// Creates a point at [x], [y].
  const FacePoint({
    required this.x,
    required this.y,
  });

  /// Horizontal coordinate in pixels.
  final double x;

  /// Vertical coordinate in pixels.
  final double y;

  /// Returns this point scaled independently on both axes.
  FacePoint scaled({
    required double scaleX,
    required double scaleY,
  }) => FacePoint(x: x * scaleX, y: y * scaleY);

  @override
  bool operator ==(Object other) => other is FacePoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'FacePoint(x: $x, y: $y)';
}
