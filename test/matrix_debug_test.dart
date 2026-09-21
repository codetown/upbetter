import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matrix scale semantics', () {
    final a = Matrix4.identity()
      ..translateByDouble(180, 20, 0, 1)
      ..scaleByDouble(0.75, 0.75, 1, 1);
    final b = Matrix4.identity()
      ..scaleByDouble(0.75, 0.75, 1, 1)
      ..translateByDouble(180, 20, 0, 1);

    print('a=$a, scale=${a.getMaxScaleOnAxis()}');
    print('b=$b, scale=${b.getMaxScaleOnAxis()}');
  });
}
