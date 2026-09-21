import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upbetter/src/ui/panels/compare_canvas.dart';

void main() {
  group('CompareCanvas 变换稳定性', () {
    test('已完全适配到视口时，拖拽不应改变缩放尺度', () {
      const logical = Size(1600, 900);
      final viewport = const Rect.fromLTWH(180, 20, 1200, 900);

      final fitScale = CompareCanvas.fitScaleFor(logical, viewport);
      expect(fitScale, closeTo(0.75, 1e-6));

      final matrix = CompareCanvas.composeMatrix(
        viewport.left + (viewport.width - logical.width * fitScale) / 2,
        viewport.top + (viewport.height - logical.height * fitScale) / 2,
        fitScale,
      );

      final next = CompareCanvas.constrainPan(
        matrix,
        logicalSize: logical,
        viewport: viewport,
        delta: const Offset(80, -35),
      );

      expect(CompareCanvas.scaleOf(next), closeTo(fitScale, 1e-6));
      expect(next.storage[12], closeTo(matrix.storage[12] + 80, 1e-5));
      expect(next.storage[13], closeTo(matrix.storage[13] - 35, 1e-5));
    });

    test('当图片本身小于画布时，最小缩放不能低于原始尺寸', () {
      const logical = Size(400, 300);
      final viewport = const Rect.fromLTWH(0, 0, 1200, 900);

      expect(CompareCanvas.minimumScaleFor(logical, viewport), 1.0);
      expect(
        CompareCanvas.minimumScaleFor(const Size(1600, 900), viewport),
        closeTo(0.75, 1e-6),
      );
    });
  });
}
