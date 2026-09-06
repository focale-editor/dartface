import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartface/src/detector/classical_face_detection_engine.dart';
import 'package:dartface/src/exceptions/dartface_exception.dart';
import 'package:dartface/src/image/face_image.dart';
import 'package:dartface/src/model/detected_face.dart';
import 'package:dartface/src/model/face_detector_options.dart';
import 'package:imcodec/imcodec.dart' as imcodec;

/// Whether this library was compiled for a JavaScript-based web runtime.
const bool _isWebRuntime = bool.fromEnvironment('dart.library.js_interop');

/// Detects mostly frontal faces without a machine-learning runtime.
final class FaceDetector {
  /// Creates a ready-to-use detector.
  FaceDetector({
    this.options = const FaceDetectorOptions(),
  });

  /// Creates a detector through the asynchronous construction style used by
  /// inference-backed face detection packages.
  static Future<FaceDetector> create({
    FaceDetectorOptions options = const FaceDetectorOptions(),
  }) => Future<FaceDetector>.value(FaceDetector(options: options));

  /// Configuration shared by every detection performed by this instance.
  final FaceDetectorOptions options;

  /// Stateless implementation used for synchronous raw-pixel calls.
  static const ClassicalFaceDetectionEngine _engine = ClassicalFaceDetectionEngine();

  /// Whether [close] or [dispose] has been called.
  bool _closed = false;

  /// Detects faces synchronously in an immutable raw image.
  List<DetectedFace> detectFaces(FaceImage image) {
    _ensureOpen();
    return _engine.detect(
      rgbaBytes: image.rgbaView,
      width: image.width,
      height: image.height,
      options: options,
    );
  }

  /// Detects faces asynchronously in an immutable raw image.
  Future<List<DetectedFace>> detectFacesAsync(FaceImage image) async {
    _ensureOpen();
    if (!options.runInIsolate || _isWebRuntime) {
      return _engine.detect(rgbaBytes: image.rgbaView, width: image.width, height: image.height, options: options);
    }
    // Only plain values are captured below. Reaching through `image` or
    // `this` inside the closure would make `Isolate.run` copy the pixel buffer
    // a second time, next to the transfer that already moves it.
    final int width = image.width;
    final int height = image.height;
    final FaceDetectorOptions detectionOptions = options;
    final TransferableTypedData transferablePixels = TransferableTypedData.fromList(<Uint8List>[image.rgbaView]);
    return Isolate.run(
      () => _detectRgbaInWorker(
        rgbaBytes: transferablePixels.materialize().asUint8List(),
        width: width,
        height: height,
        options: detectionOptions,
      ),
    );
  }

  /// Detects faces synchronously in an [imcodec.Image].
  ///
  /// This path avoids encoding and decoding when the caller already uses the
  /// Focale image stack. The detector never mutates [image].
  List<DetectedFace> detectFacesFromImage(imcodec.Image image) {
    _ensureOpen();
    return _engine.detect(
      rgbaBytes: image.bytes,
      width: image.width,
      height: image.height,
      options: options,
    );
  }

  /// Decodes supported image bytes with Imcodec and detects faces off the UI
  /// isolate when the platform and [FaceDetectorOptions.runInIsolate] allow it.
  Future<List<DetectedFace>> detectFacesFromBytes(Uint8List bytes) async {
    _ensureOpen();
    if (!options.runInIsolate || _isWebRuntime) {
      return _detectEncodedInWorker(bytes: bytes, options: options);
    }
    final FaceDetectorOptions detectionOptions = options;
    final TransferableTypedData transferableBytes = TransferableTypedData.fromList(<Uint8List>[bytes]);
    return Isolate.run(
      () => _detectEncodedInWorker(
        bytes: transferableBytes.materialize().asUint8List(),
        options: detectionOptions,
      ),
    );
  }

  /// Decodes supported image bytes with Imcodec and detects faces synchronously.
  List<DetectedFace> detectFacesFromBytesSync(Uint8List bytes) {
    _ensureOpen();
    return _detectEncodedInWorker(bytes: bytes, options: options);
  }

  /// Marks this detector as closed.
  ///
  /// Closing is idempotent. It exists for migration compatibility even though
  /// the model-free engine owns no native resources.
  void close() {
    _closed = true;
  }

  /// Closes this detector through an awaitable API.
  Future<void> dispose() {
    close();
    return Future<void>.value();
  }

  /// Rejects work submitted after this detector has been closed.
  void _ensureOpen() {
    if (_closed) {
      throw const FaceDetectorClosedException();
    }
  }
}

/// Decodes bytes and runs detection in either the caller or a worker isolate.
List<DetectedFace> _detectEncodedInWorker({
  required Uint8List bytes,
  required FaceDetectorOptions options,
}) {
  try {
    final imcodec.Image image = imcodec.decodeImage(bytes, maxPixels: options.maximumDecodedPixels);
    return _detectRgbaInWorker(
      rgbaBytes: image.bytes,
      width: image.width,
      height: image.height,
      options: options,
    );
  } on imcodec.ImageCodecException catch (error) {
    throw FaceImageDecodingException('Unable to decode the supplied image', cause: error);
  } on RangeError catch (error) {
    throw FaceImageDecodingException('The encoded image exceeds its configured safety limit', cause: error);
  }
}

/// Runs the stateless detector on straight-alpha RGBA pixels.
List<DetectedFace> _detectRgbaInWorker({
  required Uint8List rgbaBytes,
  required int width,
  required int height,
  required FaceDetectorOptions options,
}) => const ClassicalFaceDetectionEngine().detect(
  rgbaBytes: rgbaBytes,
  width: width,
  height: height,
  options: options,
);
