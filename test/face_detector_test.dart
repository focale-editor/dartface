import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:dartface/dartface.dart';
import 'package:imcodec/imcodec.dart' as imcodec;
import 'package:test/test.dart';

import 'support/synthetic_face.dart';

void main() {
  group('FaceDetector', () {
    test('detects a frontal face and its six landmarks from raw pixels', () {
      final FaceImage image = syntheticPortrait();
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.accurate,
          confidenceThreshold: 0.50,
          minimumFaceSize: 0.25,
          enableHeuristicFallback: true,
        ),
      );

      final List<DetectedFace> faces = detector.detectFaces(image);

      check(faces).isNotEmpty();
      final DetectedFace face = faces.first;
      check(face.boundingBox.center.x).isCloseTo(120, 28);
      check(face.boundingBox.center.y).isCloseTo(88, 28);
      check(face.landmarks.length).equals(6);
      check(face.landmark(FaceLandmarkType.leftEye)).isNotNull();
      check(face.landmark(FaceLandmarkType.rightEye)).isNotNull();
      check(face.landmark(FaceLandmarkType.mouthCenter)).isNotNull();
      check(face.confidence).isGreaterOrEqual(0.50);
    });

    test('detects separate faces and honors maximumFaces', () {
      final FaceImage image = syntheticPortrait(
        width: 320,
        height: 180,
        faces: const <SyntheticFacePlacement>[
          SyntheticFacePlacement(centerX: 83, centerY: 91, radiusX: 38, radiusY: 52),
          SyntheticFacePlacement(centerX: 238, centerY: 88, radiusX: 46, radiusY: 61),
        ],
      );
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.accurate,
          confidenceThreshold: 0.48,
          minimumFaceSize: 0.20,
          maximumFaces: 2,
          enableHeuristicFallback: true,
        ),
      );

      final List<DetectedFace> faces = detector.detectFaces(image);

      check(faces.length).equals(2);
      check(faces.map((face) => face.boundingBox.center.x)).any((centerX) => centerX.isLessThan(150));
      check(faces.map((face) => face.boundingBox.center.x)).any((centerX) => centerX.isGreaterThan(170));
    });

    test('rejects a flat image without facial structure', () {
      final FaceImage image = FaceImage.fromBytes(
        width: 160,
        height: 120,
        bytes: Uint8List.fromList(List<int>.filled(160 * 120, 180)),
        pixelFormat: FacePixelFormat.grayscale,
      );
      for (final FaceDetectionAccuracy accuracy in FaceDetectionAccuracy.values) {
        final FaceDetector detector = FaceDetector(
          options: FaceDetectorOptions(accuracy: accuracy),
        );

        final List<DetectedFace> faces = detector.detectFaces(image);

        check(faces).isEmpty();
      }
    });

    test('transfers raw pixels to a worker isolate', () async {
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          minimumFaceSize: 0.25,
          confidenceThreshold: 0.48,
          enableHeuristicFallback: true,
        ),
      );

      final List<DetectedFace> faces = await detector.detectFacesAsync(syntheticPortrait());

      check(faces).isNotEmpty();
    });

    test('decodes PNG through Imcodec in a worker isolate', () async {
      final FaceImage image = syntheticPortrait();
      final Uint8List encoded = encodeSyntheticPng(image);
      final FaceDetector detector = await FaceDetector.create(
        options: const FaceDetectorOptions(
          confidenceThreshold: 0.48,
          minimumFaceSize: 0.25,
          enableHeuristicFallback: true,
        ),
      );

      final List<DetectedFace> faces = await detector.detectFacesFromBytes(encoded);

      check(faces).isNotEmpty();
      await detector.dispose();
    });

    test('accepts a Focale image without re-encoding', () {
      final FaceImage source = syntheticPortrait();
      final imcodec.Image image = imcodec.Image.fromRgba(
        width: source.width,
        height: source.height,
        bytes: source.rgbaBytes,
        copy: false,
      );
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          minimumFaceSize: 0.25,
          confidenceThreshold: 0.48,
          enableHeuristicFallback: true,
        ),
      );

      final List<DetectedFace> faces = detector.detectFacesFromImage(image);

      check(faces).isNotEmpty();
    });

    test('wraps unsupported image bytes in a Dartface exception', () async {
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(runInIsolate: false),
      );

      await check(detector.detectFacesFromBytes(Uint8List.fromList(<int>[1, 2, 3]))).throws<FaceImageDecodingException>();
    });

    test('enforces the decoded-pixel safety limit', () {
      final Uint8List encoded = encodeSyntheticPng(syntheticPortrait(width: 64, height: 64));
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          maximumDecodedPixels: 100,
          runInIsolate: false,
        ),
      );

      check(() => detector.detectFacesFromBytesSync(encoded)).throws<FaceImageDecodingException>();
    });

    test('rejects calls made after disposal', () async {
      final FaceDetector detector = FaceDetector();
      await detector.dispose();

      check(() => detector.detectFaces(syntheticPortrait())).throws<FaceDetectorClosedException>();
    });
  });
}
