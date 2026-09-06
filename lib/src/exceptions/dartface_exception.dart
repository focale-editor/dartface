/// Base class for failures reported by Dartface.
sealed class DartfaceException implements Exception {
  /// Creates a failure with a readable [message] and optional [cause].
  const DartfaceException(this.message, {this.cause});

  /// Description of the failed operation.
  final String message;

  /// Original failure when one was available.
  final Object? cause;

  @override
  String toString() => cause == null ? '$runtimeType: $message' : '$runtimeType: $message ($cause)';
}

/// Reports image bytes that cannot be decoded safely.
final class FaceImageDecodingException extends DartfaceException {
  /// Creates an image decoding failure.
  const FaceImageDecodingException(super.message, {super.cause});
}

/// Reports an operation attempted after a detector was closed.
final class FaceDetectorClosedException extends DartfaceException {
  /// Creates a detector lifecycle failure.
  const FaceDetectorClosedException() : super('The detector has already been closed');
}
