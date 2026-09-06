import 'dart:io';

import 'package:dartface/dartface.dart';

import 'corpus.dart';

/// Reports landmark accuracy over the reference corpus.
///
/// Run it with `dart run test/corpus/measure_landmarks.dart` after touching the
/// landmark estimator. It prints the normalized mean error, which is the mean
/// landmark distance divided by the distance between both eyes, split between
/// the faces the estimator was tuned on and the faces that were labelled
/// afterwards and took no part in that tuning.
void main() {
  for (final FaceDetectionAccuracy accuracy in FaceDetectionAccuracy.values) {
    double tunedTotal = 0;
    double heldOutTotal = 0;
    double rollTotal = 0;
    int tunedCount = 0;
    int heldOutCount = 0;
    final StringBuffer rows = StringBuffer();
    for (final CorpusEntry entry in corpus) {
      if (!entry.accuracies.contains(accuracy)) {
        continue;
      }
      final List<DetectedFace> faces = FaceDetector(options: entry.optionsFor(accuracy)).detectFacesFromBytesSync(entry.readBytes());
      for (final ExpectedFace expected in entry.expectedFaces) {
        final ExpectedLandmarks? truth = expected.landmarks;
        if (truth == null) {
          continue;
        }
        final Iterable<DetectedFace> matched = faces.where(expected.matches);
        if (matched.isEmpty) {
          continue;
        }
        final DetectedFace face = matched.first;
        final double nme = truth.normalizedMeanError(face);
        final double rollError = (face.rollDegrees - truth.rollDegrees).abs();
        rollTotal += rollError;
        final bool heldOut = !expected.landmarksUsedForTuning;
        if (heldOut) {
          heldOutTotal += nme;
          heldOutCount++;
        } else {
          tunedTotal += nme;
          tunedCount++;
        }
        rows.writeln('  ${entry.fileName.padRight(31)} ${heldOut ? 'held-out' : 'tuned   '} NME=${nme.toStringAsFixed(3)} rollErr=${rollError.toStringAsFixed(1)}');
      }
    }
    final int total = tunedCount + heldOutCount;
    stdout.writeln(
      '${accuracy.name}: tuned NME=${(tunedTotal / tunedCount).toStringAsFixed(3)} ($tunedCount)'
      '${heldOutCount > 0 ? '  held-out NME=${(heldOutTotal / heldOutCount).toStringAsFixed(3)} ($heldOutCount)' : ''}'
      '  mean roll error=${(rollTotal / total).toStringAsFixed(1)} deg',
    );
    stdout.write(rows.toString());
  }
}
