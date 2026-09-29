import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/features/heart_rate/measure_screen.dart';

/// A patch the size the cheek regions come out at on this phone.
Rect patchAt(double x, double y) => Rect.fromCenter(
  center: Offset(x, y),
  width: 40,
  height: 36,
);

void main() {
  group('followRect', () {
    test('a still head settles onto the detected position', () {
      var current = patchAt(100, 100);
      const target = Rect.fromLTRB(110, 110, 150, 146);
      for (int i = 0; i < 60; i++) {
        current = followRect(current, target);
      }
      expect(current.left, closeTo(target.left, 0.5));
      expect(current.top, closeTo(target.top, 0.5));
    });

    test('detector wobble moves the patch far less than the wobble itself', () {
      // ML Kit jitters by a pixel or two between detections. Left unsmoothed
      // the patch follows every one of those jumps.
      final random = Random(4);
      var smoothed = patchAt(100, 100);
      var worstSmoothed = 0.0;
      var worstRaw = 0.0;
      var previousRaw = patchAt(100, 100);

      for (int i = 0; i < 200; i++) {
        final fresh = patchAt(
          100 + random.nextDouble() * 4 - 2,
          100 + random.nextDouble() * 4 - 2,
        );
        final next = followRect(smoothed, fresh);
        worstSmoothed = max(worstSmoothed, (next.center - smoothed.center).distance);
        worstRaw = max(worstRaw, (fresh.center - previousRaw.center).distance);
        smoothed = next;
        previousRaw = fresh;
      }

      expect(worstSmoothed, lessThan(worstRaw / 3));
    });

    test('a genuine head movement is followed immediately', () {
      // Half a patch width away is no longer wobble. Easing towards it would
      // drag the patch over hair and background for several frames.
      final current = patchAt(100, 100);
      final moved = patchAt(160, 100);
      expect(followRect(current, moved), equals(moved));
    });

    test('a movement just under the threshold is still eased', () {
      final current = patchAt(100, 100);
      final nudged = patchAt(115, 100);
      final result = followRect(current, nudged);
      expect(result, isNot(equals(nudged)));
      expect(result.center.dx, greaterThan(current.center.dx));
      expect(result.center.dx, lessThan(nudged.center.dx));
    });

    test('the patch keeps its size while easing', () {
      var current = patchAt(100, 100);
      final target = patchAt(112, 108);
      for (int i = 0; i < 10; i++) {
        current = followRect(current, target);
        expect(current.width, closeTo(target.width, 0.01));
        expect(current.height, closeTo(target.height, 0.01));
      }
    });
  });

  group('steadyRois', () {
    test('smooths every patch it is given', () {
      final previous = [patchAt(100, 100), patchAt(200, 100), patchAt(300, 100)];
      final fresh = [patchAt(102, 100), patchAt(202, 100), patchAt(302, 100)];
      final result = steadyRois(previous, fresh);

      expect(result, hasLength(3));
      for (int i = 0; i < 3; i++) {
        expect(result[i].center.dx, greaterThan(previous[i].center.dx));
        expect(result[i].center.dx, lessThan(fresh[i].center.dx));
      }
    });

    test('takes the fresh patches when the face was not being tracked', () {
      // The first detection of a capture, and after the face leaves frame.
      final fresh = [patchAt(100, 100), patchAt(200, 100), patchAt(300, 100)];
      expect(steadyRois(const [], fresh), equals(fresh));
    });
  });
}
