import 'package:checks/checks.dart';
import 'package:dartface/dartface.dart';
import 'package:test/test.dart';

void main() {
  group('FacePoint and FaceLandmark', () {
    test('scale independently on both axes', () {
      const FacePoint point = FacePoint(x: 3, y: 5);
      const FaceLandmark landmark = FaceLandmark(
        position: point,
        confidence: 0.8,
      );

      final FaceLandmark scaled = landmark.scaled(scaleX: 2, scaleY: 3);

      check(scaled.position).equals(const FacePoint(x: 6, y: 15));
      check(scaled.confidence).equals(0.8);
      check(point.toString()).contains('x: 3.0');
      check(landmark.toString()).contains('confidence: 0.8');
    });
  });

  group('FaceBoundingBox', () {
    test('computes edges, center, and overlap', () {
      const FaceBoundingBox first = FaceBoundingBox(left: 10, top: 20, width: 20, height: 20);
      const FaceBoundingBox second = FaceBoundingBox(left: 20, top: 20, width: 20, height: 20);

      check(first.right).equals(30);
      check(first.bottom).equals(40);
      check(first.center).equals(const FacePoint(x: 20, y: 30));
      check(first.corners).deepEquals(<FacePoint>[
        const FacePoint(x: 10, y: 20),
        const FacePoint(x: 30, y: 20),
        const FacePoint(x: 30, y: 40),
        const FacePoint(x: 10, y: 40),
      ]);
      check(first.intersectionOverUnion(second)).isCloseTo(1 / 3, 0.000001);
    });

    test('clamps every edge to the source image', () {
      const FaceBoundingBox outside = FaceBoundingBox(left: -4, top: 2, width: 20, height: 20);

      final FaceBoundingBox clamped = outside.clamped(imageWidth: 12, imageHeight: 10);

      check(clamped).equals(const FaceBoundingBox(left: 0, top: 2, width: 12, height: 8));
    });
  });

  group('DetectedFace', () {
    test('owns its landmark map and exposes migration getters', () {
      final Map<FaceLandmarkType, FaceLandmark> mutableLandmarks = <FaceLandmarkType, FaceLandmark>{
        FaceLandmarkType.noseTip: const FaceLandmark(
          position: FacePoint(x: 12, y: 18),
          confidence: 0.7,
        ),
        FaceLandmarkType.mouthCenter: const FaceLandmark(
          position: FacePoint(x: 12, y: 24),
          confidence: 0.9,
        ),
      };
      final DetectedFace face = DetectedFace(
        boundingBox: const FaceBoundingBox(left: 5, top: 8, width: 20, height: 30),
        confidence: 0.75,
        landmarks: mutableLandmarks,
        imageWidth: 100,
        imageHeight: 80,
        rollDegrees: 2,
      );
      mutableLandmarks.clear();

      check(face.score).equals(0.75);
      check(face.landmarkConfidence).isCloseTo(0.8, 0.000001);
      check(face.widthFraction).equals(0.2);
      check(face.landmark(FaceLandmarkType.noseTip)).isNotNull();
      check(face.landmarks.clear).throws<UnsupportedError>();
      check(face.toString()).contains('confidence: 0.75');
    });

    test('reports zero landmark confidence when no estimate is available', () {
      final DetectedFace face = DetectedFace(
        boundingBox: const FaceBoundingBox(
          left: 0,
          top: 0,
          width: 10,
          height: 10,
        ),
        confidence: 0.6,
        landmarks: const <FaceLandmarkType, FaceLandmark>{},
        imageWidth: 10,
        imageHeight: 10,
        rollDegrees: 0,
      );

      check(face.landmarkConfidence).equals(0);
    });
  });

  test('Dartface exceptions retain their cause', () {
    const FormatException cause = FormatException('bad bytes');
    const FaceImageDecodingException exception = FaceImageDecodingException(
      'Decode failed',
      cause: cause,
    );

    check(exception.cause).identicalTo(cause);
    check(exception.toString()).contains('bad bytes');
  });
}
