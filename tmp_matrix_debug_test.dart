import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspect matrix', () {
    final a = Matrix4.identity()
      ..translateByDouble(180, 20, 0, 1)
      ..scaleByDouble(0.75, 0.75, 1, 1);
    print('a scale=${a.getMaxScaleOnAxis()} storage=${a.storage}');

    final b = Matrix4.identity()
      ..scaleByDouble(0.75, 0.75, 1, 1)
      ..translateByDouble(180, 20, 0, 1);
    print('b scale=${b.getMaxScaleOnAxis()} storage=${b.storage}');

    final c = Matrix4.identity()
      ..setEntry(3, 0, 0)
      ..setEntry(3, 1, 0)
      ..setEntry(0, 0, 0.75)
      ..setEntry(1, 1, 0.75)
      ..setEntry(2, 2, 1)
      ..setEntry(3, 2, 0)
      ..setEntry(0, 3, 180)
      ..setEntry(1, 3, 20);
    print('c scale=${c.getMaxScaleOnAxis()} storage=${c.storage}');
  });
}
