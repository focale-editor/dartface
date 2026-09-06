import 'package:checks/checks.dart';
import 'package:dartface/src/detector/generated/lbp_frontal_face_cascade.dart';
import 'package:test/test.dart';

void main() {
  test('generated LBP cascade tables remain internally consistent', () {
    final int weakClassifierCount = lbpStageWeakCounts.fold(0, (sum, count) => sum + count);
    final int featureCount = lbpFeatureRectangles.length ~/ 4;

    check(lbpCascadeWidth).equals(45);
    check(lbpCascadeHeight).equals(45);
    check(lbpStageThresholds.length).equals(lbpStageWeakCounts.length);
    check(lbpWeakFeatureIndexes.length).equals(weakClassifierCount);
    check(lbpWeakCategoryMasks.length).equals(weakClassifierCount * 8);
    check(lbpWeakLeftValues.length).equals(weakClassifierCount);
    check(lbpWeakRightValues.length).equals(weakClassifierCount);
    check(lbpFeatureRectangles.length.remainder(4)).equals(0);
    check(lbpWeakFeatureIndexes).every((featureIndex) {
      featureIndex.isGreaterOrEqual(0);
      featureIndex.isLessThan(featureCount);
    });
  });

  test('every stage evaluates at least one weak classifier', () {
    // The evaluator divides a stage margin by this count, so a zero would turn
    // one stage score into a non-finite value.
    check(lbpStageWeakCounts).isNotEmpty();
    check(lbpStageWeakCounts).every((count) => count.isGreaterThan(0));
  });

  test('every feature cell grid fits inside the detection window', () {
    // The evaluator reads a three-by-three cell grid per feature without
    // clamping, so a rectangle reaching past the window would read the wrong
    // pixels in release builds, where the bounds assertions are stripped.
    for (int featureIndex = 0; featureIndex * 4 < lbpFeatureRectangles.length; featureIndex++) {
      final int offset = featureIndex * 4;
      final int x = lbpFeatureRectangles[offset];
      final int y = lbpFeatureRectangles[offset + 1];
      final int cellWidth = lbpFeatureRectangles[offset + 2];
      final int cellHeight = lbpFeatureRectangles[offset + 3];

      check(because: 'feature $featureIndex starts at ($x, $y)', x).isGreaterOrEqual(0);
      check(because: 'feature $featureIndex starts at ($x, $y)', y).isGreaterOrEqual(0);
      check(because: 'feature $featureIndex has a ${cellWidth}x$cellHeight cell', cellWidth).isGreaterThan(0);
      check(because: 'feature $featureIndex has a ${cellWidth}x$cellHeight cell', cellHeight).isGreaterThan(0);
      check(because: 'feature $featureIndex overflows the window width', x + 3 * cellWidth).isLessOrEqual(lbpCascadeWidth);
      check(because: 'feature $featureIndex overflows the window height', y + 3 * cellHeight).isLessOrEqual(lbpCascadeHeight);
    }
  });
}
