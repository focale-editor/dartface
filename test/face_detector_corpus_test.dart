import 'dart:math' as math;
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:dartface/dartface.dart';
import 'package:imcodec/imcodec.dart' as imcodec;
import 'package:test/test.dart';

import 'corpus/corpus.dart';

void main() {
  group('LBP cascade on public-domain photographs', () {
    for (final CorpusEntry entry in corpus) {
      for (final FaceDetectionAccuracy accuracy in entry.accuracies) {
        test('finds every expected face in ${entry.fileName} at ${accuracy.name}', () {
          final FaceDetector detector = FaceDetector(options: entry.optionsFor(accuracy));

          final List<DetectedFace> faces = detector.detectFacesFromBytesSync(entry.readBytes());

          check(because: 'reported ${faces.length} faces: $faces', faces.length).equals(entry.expectedFaces.length);
          for (final ExpectedFace expected in entry.expectedFaces) {
            check(
              because: '$expected was not covered by $faces',
              faces.any(expected.matches),
            ).isTrue();
          }
          for (final DetectedFace face in faces) {
            check(face.imageWidth).equals(entry.width);
            check(face.imageHeight).equals(entry.height);
            check(face.boundingBox.left).isGreaterOrEqual(0);
            check(face.boundingBox.top).isGreaterOrEqual(0);
            check(face.boundingBox.right).isLessOrEqual(entry.width.toDouble());
            check(face.boundingBox.bottom).isLessOrEqual(entry.height.toDouble());
            check(face.confidence).isGreaterOrEqual(entry.optionsFor(accuracy).confidenceThreshold);
          }
        });
      }
    }

    for (final CorpusEntry entry in negativeCorpus) {
      test('reports nothing in ${entry.fileName}', () {
        for (final FaceDetectionAccuracy accuracy in entry.accuracies) {
          final FaceDetector detector = FaceDetector(options: entry.optionsFor(accuracy));

          final List<DetectedFace> faces = detector.detectFacesFromBytesSync(entry.readBytes());

          check(because: '${accuracy.name} reported $faces', faces).isEmpty();
        }
      });
    }

    for (final FaceDetectionAccuracy accuracy in FaceDetectionAccuracy.values) {
      test('estimates landmarks and roll accurately at ${accuracy.name}', () {
        // Errors are normalized by the distance between both eyes, which is
        // the usual scale for face-alignment benchmarks. The bounds sit well
        // above the measured values so that the test catches a regression
        // rather than locking in exact numbers.
        double errorSum = 0;
        double rollErrorSum = 0;
        int count = 0;
        for (final CorpusEntry entry in corpus) {
          if (!entry.accuracies.contains(accuracy)) {
            continue;
          }
          final FaceDetector detector = FaceDetector(options: entry.optionsFor(accuracy));
          final List<DetectedFace> faces = detector.detectFacesFromBytesSync(entry.readBytes());
          for (final ExpectedFace expected in entry.expectedFaces) {
            final ExpectedLandmarks? truth = expected.landmarks;
            if (truth == null) {
              continue;
            }
            final DetectedFace face = faces.firstWhere(expected.matches);
            final double error = truth.normalizedMeanError(face);
            final double rollError = (face.rollDegrees - truth.rollDegrees).abs();

            check(because: '${entry.fileName} landmark error', error).isLessThan(0.17);
            check(because: '${entry.fileName} roll error', rollError).isLessThan(10);
            errorSum += error;
            rollErrorSum += rollError;
            count++;
          }
        }

        check(count).isGreaterThan(4);
        check(because: 'mean landmark error over $count faces', errorSum / count).isLessThan(0.11);
        check(because: 'mean roll error over $count faces', rollErrorSum / count).isLessThan(5);
      });
    }

    test('places the six landmarks consistently inside each face', () {
      final CorpusEntry entry = corpus.first;
      final FaceDetector detector = FaceDetector(options: entry.optionsFor(FaceDetectionAccuracy.accurate));

      final DetectedFace face = detector.detectFacesFromBytesSync(entry.readBytes()).single;

      check(face.landmarks.keys).unorderedEquals(FaceLandmarkType.values);
      for (final FaceLandmark landmark in face.landmarks.values) {
        check(landmark.position.x).isGreaterOrEqual(face.boundingBox.left - face.boundingBox.width * 0.2);
        check(landmark.position.x).isLessOrEqual(face.boundingBox.right + face.boundingBox.width * 0.2);
        check(landmark.position.y).isGreaterOrEqual(face.boundingBox.top);
        check(landmark.position.y).isLessOrEqual(face.boundingBox.bottom);
      }
      final FaceLandmark leftEye = face.landmark(FaceLandmarkType.leftEye)!;
      final FaceLandmark rightEye = face.landmark(FaceLandmarkType.rightEye)!;
      final FaceLandmark mouth = face.landmark(FaceLandmarkType.mouthCenter)!;
      check(leftEye.position.x).isLessThan(rightEye.position.x);
      check(mouth.position.y).isGreaterThan(leftEye.position.y);
      check(mouth.position.y).isGreaterThan(rightEye.position.y);
      check(face.landmark(FaceLandmarkType.mouthLeft)!.position.x).isLessThan(mouth.position.x);
      check(face.landmark(FaceLandmarkType.mouthRight)!.position.x).isGreaterThan(mouth.position.x);
    });

    test('returns the same faces for repeated calls and for the isolate path', () async {
      final CorpusEntry entry = corpus.first;
      final Uint8List bytes = entry.readBytes();
      final FaceDetector detector = FaceDetector(options: entry.optionsFor(FaceDetectionAccuracy.balanced));

      final List<DetectedFace> first = detector.detectFacesFromBytesSync(bytes);
      final List<DetectedFace> second = detector.detectFacesFromBytesSync(bytes);
      final List<DetectedFace> viaIsolate = await FaceDetector(
        options: const FaceDetectorOptions(minimumFaceSize: 0.15, maximumFaces: 40),
      ).detectFacesFromBytes(bytes);

      check(second.map((face) => face.boundingBox)).deepEquals(first.map((face) => face.boundingBox));
      check(viaIsolate.map((face) => face.boundingBox)).deepEquals(first.map((face) => face.boundingBox));
    });

    test('keeps one real face and rejects unstable geometry after mirroring', () {
      final CorpusEntry entry = corpus.firstWhere(
        (candidate) => candidate.fileName == 'portrait_michelle_obama.jpg',
      );
      final imcodec.Image decoded = imcodec.decodeImage(entry.readBytes());
      final FaceImage mirroredImage = _mirrorHorizontally(decoded);
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.balanced,
          minimumFaceSize: 0.15,
          maximumFaces: 40,
          runInIsolate: false,
        ),
      );

      final List<DetectedFace> faces = detector.detectFaces(mirroredImage);

      check(faces.length).equals(1);
      check(
        const ExpectedFace(centerX: 257, centerY: 211, size: 106).matches(
          faces.single,
        ),
      ).isTrue();
      check(faces.single.landmarkConfidence).isGreaterOrEqual(0.40);
    });

    test('honors the aggregate landmark-confidence threshold', () {
      final CorpusEntry entry = corpus.firstWhere(
        (candidate) => candidate.fileName == 'portrait_michelle_obama.jpg',
      );
      final DetectedFace baseline = FaceDetector(
        options: entry.optionsFor(FaceDetectionAccuracy.balanced),
      ).detectFacesFromBytesSync(entry.readBytes()).single;
      check(baseline.landmarkConfidence).isLessThan(1);
      final double stricterThreshold = (baseline.landmarkConfidence + 1) / 2;
      final FaceDetector strictDetector = FaceDetector(
        options: FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.balanced,
          minimumFaceSize: entry.minimumFaceSize,
          minimumLandmarkConfidence: stricterThreshold,
          maximumFaces: 40,
          runInIsolate: false,
        ),
      );

      final List<DetectedFace> faces = strictDetector.detectFacesFromBytesSync(
        entry.readBytes(),
      );

      check(faces).isEmpty();
    });

    test('derives roll from source-space landmark coordinates', () {
      final CorpusEntry entry = corpus.firstWhere(
        (candidate) => candidate.fileName == 'portrait_marie_curie.jpg',
      );
      final DetectedFace face = FaceDetector(
        options: entry.optionsFor(FaceDetectionAccuracy.balanced),
      ).detectFacesFromBytesSync(entry.readBytes()).single;
      final FacePoint leftEye = face.landmark(FaceLandmarkType.leftEye)!.position;
      final FacePoint rightEye = face.landmark(FaceLandmarkType.rightEye)!.position;
      final double sourceSpaceRoll =
          math.atan2(
            rightEye.y - leftEye.y,
            rightEye.x - leftEye.x,
          ) *
          180 /
          math.pi;

      check(face.rollDegrees).isCloseTo(sourceSpaceRoll, 0.000000001);
    });

    test('accurate rotation recovery finds a strongly tilted face', () {
      final CorpusEntry entry = corpus.firstWhere(
        (candidate) => candidate.fileName == 'group_obama_family.jpg',
      );
      final ExpectedFace tiltedFace = entry.expectedFaces.last;
      final FaceDetector withoutRecovery = FaceDetector(
        options: FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.accurate,
          minimumFaceSize: entry.minimumFaceSize,
          maximumFaces: 40,
          runInIsolate: false,
          enableRotationRecovery: false,
        ),
      );
      final FaceDetector withRecovery = FaceDetector(
        options: entry.optionsFor(FaceDetectionAccuracy.accurate),
      );

      final List<DetectedFace> baseline = withoutRecovery.detectFacesFromBytesSync(
        entry.readBytes(),
      );
      final List<DetectedFace> recovered = withRecovery.detectFacesFromBytesSync(
        entry.readBytes(),
      );

      check(baseline.any(tiltedFace.matches)).isFalse();
      check(recovered.any(tiltedFace.matches)).isTrue();
      check(recovered.length).equals(entry.expectedFaces.length);
    });

    test('cannot resolve the faces of a large 1927 group photograph', () {
      // The faces span far fewer than the cascade's 45 working pixels. The
      // check records that limit and guards against false positives; finding
      // faces here would be an improvement, and the expectation should then
      // be updated rather than removed.
      final FaceDetector detector = FaceDetector(
        options: const FaceDetectorOptions(
          accuracy: FaceDetectionAccuracy.accurate,
          minimumFaceSize: 0.05,
          maximumFaces: 40,
          runInIsolate: false,
        ),
      );

      final List<DetectedFace> faces = detector.detectFacesFromBytesSync(
        const CorpusEntry(fileName: 'group_solvay_1927.jpg', width: 960, height: 695, expectedFaces: <ExpectedFace>[]).readBytes(),
      );

      check(faces).isEmpty();
    });
  });
}

/// Returns an owned horizontal mirror of a decoded corpus image.
FaceImage _mirrorHorizontally(imcodec.Image image) {
  final Uint8List mirrored = Uint8List(image.width * image.height * 4);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final int sourceOffset = (y * image.width + x) * 4;
      final int destinationOffset = (y * image.width + image.width - x - 1) * 4;
      mirrored.setRange(
        destinationOffset,
        destinationOffset + 4,
        image.bytes,
        sourceOffset,
      );
    }
  }
  return FaceImage.fromBytes(
    width: image.width,
    height: image.height,
    bytes: mirrored,
  );
}
