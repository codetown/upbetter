import 'package:flutter/material.dart';

void main() {
  final m = Matrix4.identity()
    ..translateByDouble(180, 20, 0, 1)
    ..scaleByDouble(0.75, 0.75, 1, 1);
  print('scale=${m.getMaxScaleOnAxis()}');
  print(m.storage);
}
