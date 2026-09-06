import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartface/dartface.dart';
import 'package:imcodec/imcodec.dart' as imcodec;

/// Creates a deterministic portrait-like fixture without external assets.
FaceImage syntheticPortrait({
  int width = 240,
  int height = 180,
  List<SyntheticFacePlacement> faces = const <SyntheticFacePlacement>[
    SyntheticFacePlacement(centerX: 120, centerY: 88, radiusX: 48, radiusY: 64),
  ],
}) {
  final Uint8List pixels = Uint8List(width * height * 4);
  _fill(pixels: pixels, red: 42, green: 66, blue: 92);
  for (final SyntheticFacePlacement face in faces) {
    _paintFace(pixels: pixels, width: width, height: height, face: face);
  }
  return FaceImage.fromBytes(
    width: width,
    height: height,
    bytes: pixels,
  );
}

/// Encodes [image] as PNG through the Focale Imcodec package.
Uint8List encodeSyntheticPng(FaceImage image) {
  final Uint8List rgba = image.rgbaBytes;
  final imcodec.Image codecImage = imcodec.Image.fromRgba(
    width: image.width,
    height: image.height,
    bytes: rgba,
    copy: false,
  );
  return imcodec.encodePng(codecImage);
}

/// Describes one synthetic face ellipse in fixture coordinates.
final class SyntheticFacePlacement {
  /// Creates an ellipse centered at [centerX], [centerY].
  const SyntheticFacePlacement({
    required this.centerX,
    required this.centerY,
    required this.radiusX,
    required this.radiusY,
  });

  /// Horizontal center in pixels.
  final int centerX;

  /// Vertical center in pixels.
  final int centerY;

  /// Horizontal face radius in pixels.
  final int radiusX;

  /// Vertical face radius in pixels.
  final int radiusY;
}

/// Paints a face with bilateral eyes, a raised nose, and a dark red mouth.
void _paintFace({
  required Uint8List pixels,
  required int width,
  required int height,
  required SyntheticFacePlacement face,
}) {
  _ellipse(
    pixels: pixels,
    width: width,
    height: height,
    centerX: face.centerX,
    centerY: face.centerY,
    radiusX: face.radiusX,
    radiusY: face.radiusY,
    red: 198,
    green: 139,
    blue: 105,
  );
  _ellipse(
    pixels: pixels,
    width: width,
    height: height,
    centerX: face.centerX,
    centerY: face.centerY - (face.radiusY * 0.78).round(),
    radiusX: (face.radiusX * 0.82).round(),
    radiusY: (face.radiusY * 0.22).round(),
    red: 45,
    green: 31,
    blue: 25,
  );

  final int eyeY = face.centerY - (face.radiusY * 0.25).round();
  final int eyeOffset = (face.radiusX * 0.39).round();
  for (final int eyeX in <int>[face.centerX - eyeOffset, face.centerX + eyeOffset]) {
    _ellipse(
      pixels: pixels,
      width: width,
      height: height,
      centerX: eyeX,
      centerY: eyeY,
      radiusX: math.max(3, (face.radiusX * 0.17).round()),
      radiusY: math.max(2, (face.radiusY * 0.07).round()),
      red: 36,
      green: 29,
      blue: 26,
    );
    _ellipse(
      pixels: pixels,
      width: width,
      height: height,
      centerX: eyeX,
      centerY: eyeY,
      radiusX: math.max(1, (face.radiusX * 0.05).round()),
      radiusY: math.max(1, (face.radiusY * 0.04).round()),
      red: 8,
      green: 8,
      blue: 8,
    );
  }

  _ellipse(
    pixels: pixels,
    width: width,
    height: height,
    centerX: face.centerX,
    centerY: face.centerY + (face.radiusY * 0.05).round(),
    radiusX: math.max(3, (face.radiusX * 0.10).round()),
    radiusY: math.max(6, (face.radiusY * 0.22).round()),
    red: 228,
    green: 171,
    blue: 126,
  );
  _ellipse(
    pixels: pixels,
    width: width,
    height: height,
    centerX: face.centerX,
    centerY: face.centerY + (face.radiusY * 0.48).round(),
    radiusX: math.max(6, (face.radiusX * 0.31).round()),
    radiusY: math.max(2, (face.radiusY * 0.07).round()),
    red: 103,
    green: 31,
    blue: 37,
  );
}

/// Fills an RGBA buffer with one opaque color.
void _fill({required Uint8List pixels, required int red, required int green, required int blue}) {
  for (int offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = red;
    pixels[offset + 1] = green;
    pixels[offset + 2] = blue;
    pixels[offset + 3] = 255;
  }
}

/// Rasterizes one hard-edged ellipse into an RGBA buffer.
void _ellipse({
  required Uint8List pixels,
  required int width,
  required int height,
  required int centerX,
  required int centerY,
  required int radiusX,
  required int radiusY,
  required int red,
  required int green,
  required int blue,
}) {
  final int left = math.max(0, centerX - radiusX);
  final int top = math.max(0, centerY - radiusY);
  final int right = math.min(width - 1, centerX + radiusX);
  final int bottom = math.min(height - 1, centerY + radiusY);
  for (int y = top; y <= bottom; y++) {
    final double normalizedY = (y - centerY) / radiusY;
    for (int x = left; x <= right; x++) {
      final double normalizedX = (x - centerX) / radiusX;
      if (normalizedX * normalizedX + normalizedY * normalizedY > 1) {
        continue;
      }
      final int offset = (y * width + x) * 4;
      pixels[offset] = red;
      pixels[offset + 1] = green;
      pixels[offset + 2] = blue;
      pixels[offset + 3] = 255;
    }
  }
}
