import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:dartface/dartface.dart';
import 'package:test/test.dart';

void main() {
  group('FaceImage', () {
    test('normalizes every packed pixel format', () {
      final List<(FacePixelFormat, List<int>)> inputs = <(FacePixelFormat, List<int>)>[
        (FacePixelFormat.grayscale, <int>[9]),
        (FacePixelFormat.rgb888, <int>[10, 20, 30]),
        (FacePixelFormat.bgr888, <int>[30, 20, 10]),
        (FacePixelFormat.rgba8888, <int>[10, 20, 30, 40]),
        (FacePixelFormat.bgra8888, <int>[30, 20, 10, 40]),
        (FacePixelFormat.argb8888, <int>[40, 10, 20, 30]),
        (FacePixelFormat.abgr8888, <int>[40, 30, 20, 10]),
      ];

      for (final (FacePixelFormat format, List<int> bytes) in inputs) {
        final FaceImage image = FaceImage.fromBytes(
          width: 1,
          height: 1,
          bytes: Uint8List.fromList(bytes),
          pixelFormat: format,
        );
        final List<int> expected = switch (format) {
          FacePixelFormat.grayscale => <int>[9, 9, 9, 255],
          FacePixelFormat.rgb888 || FacePixelFormat.bgr888 => <int>[10, 20, 30, 255],
          _ => <int>[10, 20, 30, 40],
        };

        check(image.rgbaBytes).deepEquals(expected);
      }
    });

    test('normalizes row-strided BGRA without retaining caller bytes', () {
      final Uint8List source = Uint8List.fromList(<int>[
        30,
        20,
        10,
        40,
        60,
        50,
        40,
        70,
        0,
        0,
        0,
        0,
      ]);

      final FaceImage image = FaceImage.fromBytes(
        width: 2,
        height: 1,
        bytes: source,
        pixelFormat: FacePixelFormat.bgra8888,
        rowStride: 12,
      );
      source.fillRange(0, source.length, 255);

      check(image.rgbaBytes).deepEquals(<int>[10, 20, 30, 40, 40, 50, 60, 70]);
    });

    test('copies row-strided RGBA rows without retaining caller bytes', () {
      final Uint8List source = Uint8List.fromList(<int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        90,
        91,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        92,
        93,
      ]);

      final FaceImage image = FaceImage.fromBytes(
        width: 2,
        height: 2,
        bytes: source,
        rowStride: 10,
      );
      source.fillRange(0, source.length, 255);

      check(image.rgbaBytes).deepEquals(<int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
    });

    test('returns a defensive RGBA copy', () {
      final FaceImage image = FaceImage.fromBytes(
        width: 1,
        height: 1,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      final Uint8List firstRead = image.rgbaBytes..fillRange(0, 4, 255);

      check(firstRead).deepEquals(<int>[255, 255, 255, 255]);
      check(image.rgbaBytes).deepEquals(<int>[1, 2, 3, 4]);
    });

    test('converts planar YUV420 camera data', () {
      final FaceImage image = FaceImage.fromYuv420(
        width: 2,
        height: 2,
        luminancePlane: Uint8List.fromList(<int>[82, 82, 82, 82]),
        chromaBluePlane: Uint8List.fromList(<int>[90]),
        chromaRedPlane: Uint8List.fromList(<int>[240]),
        luminanceRowStride: 2,
        chromaRowStride: 1,
      );

      final Uint8List rgba = image.rgbaBytes;
      check(rgba.length).equals(16);
      check(rgba[0]).isGreaterThan(rgba[1]);
      check(rgba[0]).isGreaterThan(rgba[2]);
      check(rgba[3]).equals(255);
    });

    test('rejects a source buffer that cannot cover the dimensions', () {
      check(
        () => FaceImage.fromBytes(
          width: 2,
          height: 2,
          bytes: Uint8List(3),
          pixelFormat: FacePixelFormat.rgb888,
        ),
      ).throws<ArgumentError>();
    });
  });
}
