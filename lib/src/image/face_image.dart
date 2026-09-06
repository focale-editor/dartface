import 'dart:typed_data';

/// Describes the byte order used by a raw image.
enum FacePixelFormat {
  /// One luminance byte per pixel.
  grayscale(channelCount: 1),

  /// Red, green, and blue bytes per pixel.
  rgb888(channelCount: 3),

  /// Blue, green, and red bytes per pixel.
  bgr888(channelCount: 3),

  /// Red, green, blue, and alpha bytes per pixel.
  rgba8888(channelCount: 4),

  /// Blue, green, red, and alpha bytes per pixel.
  bgra8888(channelCount: 4),

  /// Alpha, red, green, and blue bytes per pixel.
  argb8888(channelCount: 4),

  /// Alpha, blue, green, and red bytes per pixel.
  abgr8888(channelCount: 4);

  /// Creates a pixel layout occupying [channelCount] bytes per pixel.
  const FacePixelFormat({required this.channelCount});

  /// Number of source bytes occupied by one pixel.
  final int channelCount;
}

/// An immutable, straight-alpha RGBA image ready for face detection.
final class FaceImage {
  /// Creates an image by normalizing [bytes] to tightly packed RGBA.
  factory FaceImage.fromBytes({
    required int width,
    required int height,
    required Uint8List bytes,
    FacePixelFormat pixelFormat = FacePixelFormat.rgba8888,
    int? rowStride,
  }) {
    _validateDimensions(width: width, height: height);
    final int packedStride = width * pixelFormat.channelCount;
    final int sourceStride = rowStride ?? packedStride;
    if (sourceStride < packedStride) {
      throw RangeError.range(sourceStride, packedStride, null, 'rowStride');
    }
    final int requiredLength = (height - 1) * sourceStride + packedStride;
    if (bytes.length < requiredLength) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Expected at least $requiredLength source bytes');
    }

    final Uint8List rgba = Uint8List(width * height * 4);
    if (pixelFormat == FacePixelFormat.rgba8888) {
      for (int y = 0; y < height; y++) {
        final int sourceOffset = y * sourceStride;
        final int destinationOffset = y * packedStride;
        rgba.setRange(
          destinationOffset,
          destinationOffset + packedStride,
          bytes,
          sourceOffset,
        );
      }
      return FaceImage._(
        width: width,
        height: height,
        rgbaBytes: rgba,
      );
    }
    for (int y = 0; y < height; y++) {
      int sourceOffset = y * sourceStride;
      int destinationOffset = y * width * 4;
      for (int x = 0; x < width; x++) {
        final (int red, int green, int blue, int alpha) = _readPixel(bytes, sourceOffset, pixelFormat);
        rgba[destinationOffset] = red;
        rgba[destinationOffset + 1] = green;
        rgba[destinationOffset + 2] = blue;
        rgba[destinationOffset + 3] = alpha;
        sourceOffset += pixelFormat.channelCount;
        destinationOffset += 4;
      }
    }
    return FaceImage._(width: width, height: height, rgbaBytes: rgba);
  }

  /// Converts planar YUV420 camera data to an immutable RGBA image.
  factory FaceImage.fromYuv420({
    required int width,
    required int height,
    required Uint8List luminancePlane,
    required Uint8List chromaBluePlane,
    required Uint8List chromaRedPlane,
    required int luminanceRowStride,
    required int chromaRowStride,
    int chromaPixelStride = 1,
  }) {
    _validateDimensions(width: width, height: height);
    if (luminanceRowStride < width) {
      throw RangeError.range(luminanceRowStride, width, null, 'luminanceRowStride');
    }
    if (chromaPixelStride < 1) {
      throw RangeError.range(chromaPixelStride, 1, null, 'chromaPixelStride');
    }
    final int chromaWidth = (width + 1) ~/ 2;
    final int chromaHeight = (height + 1) ~/ 2;
    final int minimumChromaRowStride = (chromaWidth - 1) * chromaPixelStride + 1;
    if (chromaRowStride < minimumChromaRowStride) {
      throw RangeError.range(chromaRowStride, minimumChromaRowStride, null, 'chromaRowStride');
    }
    _validatePlaneLength(
      plane: luminancePlane,
      requiredLength: (height - 1) * luminanceRowStride + width,
      name: 'luminancePlane',
    );
    final int requiredChromaLength = (chromaHeight - 1) * chromaRowStride + minimumChromaRowStride;
    _validatePlaneLength(plane: chromaBluePlane, requiredLength: requiredChromaLength, name: 'chromaBluePlane');
    _validatePlaneLength(plane: chromaRedPlane, requiredLength: requiredChromaLength, name: 'chromaRedPlane');

    final Uint8List rgba = Uint8List(width * height * 4);
    for (int y = 0; y < height; y++) {
      final int luminanceRow = y * luminanceRowStride;
      final int chromaRow = (y ~/ 2) * chromaRowStride;
      for (int x = 0; x < width; x++) {
        final int chromaOffset = chromaRow + (x ~/ 2) * chromaPixelStride;
        final int luminance = luminancePlane[luminanceRow + x] - 16;
        final int chromaBlue = chromaBluePlane[chromaOffset] - 128;
        final int chromaRed = chromaRedPlane[chromaOffset] - 128;
        final int scaledLuminance = 298 * (luminance < 0 ? 0 : luminance);
        final int destinationOffset = (y * width + x) * 4;
        rgba[destinationOffset] = _clampByte((scaledLuminance + 409 * chromaRed + 128) >> 8);
        rgba[destinationOffset + 1] = _clampByte((scaledLuminance - 100 * chromaBlue - 208 * chromaRed + 128) >> 8);
        rgba[destinationOffset + 2] = _clampByte((scaledLuminance + 516 * chromaBlue + 128) >> 8);
        rgba[destinationOffset + 3] = 255;
      }
    }
    return FaceImage._(width: width, height: height, rgbaBytes: rgba);
  }

  /// Creates an image around an owned and already validated RGBA buffer.
  FaceImage._({
    required this.width,
    required this.height,
    required this._rgbaBytes,
  });

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Privately owned straight-alpha RGBA pixels.
  final Uint8List _rgbaBytes;

  /// Read-only alias of [_rgbaBytes], created once per image.
  late final Uint8List _rgbaView = _rgbaBytes.asUnmodifiableView();

  /// Returns a defensive copy of the straight-alpha RGBA pixels.
  ///
  /// Use [rgbaView] instead when the pixels are only read: this getter copies
  /// the whole buffer on every call, which is wasteful for camera frames.
  Uint8List get rgbaBytes => Uint8List.fromList(_rgbaBytes);

  /// Returns an unmodifiable view over the straight-alpha RGBA pixels.
  ///
  /// The view shares this image's buffer instead of copying it, so reads are
  /// free and writes throw [UnsupportedError].
  Uint8List get rgbaView => _rgbaView;

  /// Decodes one pixel from [bytes] according to [pixelFormat].
  static (int, int, int, int) _readPixel(Uint8List bytes, int offset, FacePixelFormat pixelFormat) => switch (pixelFormat) {
    FacePixelFormat.grayscale => (bytes[offset], bytes[offset], bytes[offset], 255),
    FacePixelFormat.rgb888 => (bytes[offset], bytes[offset + 1], bytes[offset + 2], 255),
    FacePixelFormat.bgr888 => (bytes[offset + 2], bytes[offset + 1], bytes[offset], 255),
    FacePixelFormat.rgba8888 => (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]),
    FacePixelFormat.bgra8888 => (bytes[offset + 2], bytes[offset + 1], bytes[offset], bytes[offset + 3]),
    FacePixelFormat.argb8888 => (bytes[offset + 1], bytes[offset + 2], bytes[offset + 3], bytes[offset]),
    FacePixelFormat.abgr8888 => (bytes[offset + 3], bytes[offset + 2], bytes[offset + 1], bytes[offset]),
  };

  /// Rejects empty image dimensions before allocating a pixel buffer.
  static void _validateDimensions({required int width, required int height}) {
    if (width < 1) {
      throw RangeError.range(width, 1, null, 'width');
    }
    if (height < 1) {
      throw RangeError.range(height, 1, null, 'height');
    }
  }

  /// Rejects a camera plane that cannot cover its declared dimensions.
  static void _validatePlaneLength({
    required Uint8List plane,
    required int requiredLength,
    required String name,
  }) {
    if (plane.length < requiredLength) {
      throw ArgumentError.value(plane.length, name, 'Expected at least $requiredLength bytes');
    }
  }

  /// Restricts an integer color channel to eight bits.
  static int _clampByte(int value) => value.clamp(0, 255);
}
