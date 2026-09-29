import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/features/heart_rate/measure_screen.dart';

/// Rotating the buffer by [rotation] must put [point] where ML Kit saw it.
/// Forward transform, used to generate the expected answers independently.
Offset pointInRotatedImage(Offset p, int rotation, int bufW, int bufH) {
  switch (rotation) {
    case 90:
      return Offset(bufH - p.dy, p.dx);
    case 180:
      return Offset(bufW - p.dx, bufH - p.dy);
    case 270:
      return Offset(p.dy, bufW - p.dx);
    default:
      return p;
  }
}

void main() {
  const bufW = 640;
  const bufH = 480;

  group('mapRotatedRectToBuffer', () {
    test('is a no-op when the buffer is already upright', () {
      const r = Rect.fromLTRB(10, 20, 110, 90);
      expect(mapRotatedRectToBuffer(r, 0, bufW, bufH), r);
    });

    test('round-trips a rect through every rotation', () {
      for (final rotation in [0, 90, 180, 270]) {
        // A rect somewhere inside the upright image ML Kit would have seen.
        final uprightW = (rotation == 90 || rotation == 270) ? bufH : bufW;
        final uprightH = (rotation == 90 || rotation == 270) ? bufW : bufH;
        final upright = Rect.fromLTWH(
          uprightW * 0.3,
          uprightH * 0.1,
          uprightW * 0.2,
          uprightH * 0.15,
        );

        final mapped = mapRotatedRectToBuffer(upright, rotation, bufW, bufH);

        // Mapping the corners forward again must reproduce the upright rect.
        final a = pointInRotatedImage(mapped.topLeft, rotation, bufW, bufH);
        final b = pointInRotatedImage(mapped.bottomRight, rotation, bufW, bufH);
        final back = Rect.fromPoints(a, b);

        expect(back.left, closeTo(upright.left, 0.01), reason: 'rotation $rotation');
        expect(back.top, closeTo(upright.top, 0.01), reason: 'rotation $rotation');
        expect(back.right, closeTo(upright.right, 0.01), reason: 'rotation $rotation');
        expect(back.bottom, closeTo(upright.bottom, 0.01), reason: 'rotation $rotation');
      }
    });

    test('keeps the mapped rect inside the buffer', () {
      // 270 is the usual front-camera sensor orientation.
      const forehead = Rect.fromLTRB(150, 40, 330, 150);
      final mapped = mapRotatedRectToBuffer(forehead, 270, bufW, bufH);

      expect(mapped.left, greaterThanOrEqualTo(0));
      expect(mapped.top, greaterThanOrEqualTo(0));
      expect(mapped.right, lessThanOrEqualTo(bufW.toDouble()));
      expect(mapped.bottom, lessThanOrEqualTo(bufH.toDouble()));
      expect(mapped.width, greaterThan(0));
      expect(mapped.height, greaterThan(0));
    });

    test('a forehead near the top stays near the sensor edge it belongs to', () {
      // Upright coords: 480 wide, 640 tall for a 270-rotated 640x480 buffer.
      const forehead = Rect.fromLTRB(180, 30, 300, 120);
      final mapped = mapRotatedRectToBuffer(forehead, 270, bufW, bufH);

      // Under a 270 rotation the upright top edge maps to the buffer's right.
      expect(mapped.right, closeTo(bufW - forehead.top, 0.01));
      expect(mapped.left, closeTo(bufW - forehead.bottom, 0.01));
    });

    test('produces a normalised rect, not an inverted one', () {
      for (final rotation in [0, 90, 180, 270]) {
        final mapped = mapRotatedRectToBuffer(
          const Rect.fromLTRB(100, 50, 220, 160),
          rotation,
          bufW,
          bufH,
        );
        expect(mapped.width, greaterThan(0), reason: 'rotation $rotation');
        expect(mapped.height, greaterThan(0), reason: 'rotation $rotation');
      }
    });
  });
}
