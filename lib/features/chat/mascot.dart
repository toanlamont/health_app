import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// "Tim", the assistant's mascot: a smiling heart, drawn rather than shipped
/// as an image so it stays sharp at any size and needs no asset.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MascotPainter());
}

class _MascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final heart = Path()
      ..moveTo(w * .5, h * .9)
      ..cubicTo(w * .12, h * .66, w * .02, h * .44, w * .1, h * .28)
      ..cubicTo(w * .19, h * .1, w * .42, h * .1, w * .5, h * .28)
      ..cubicTo(w * .58, h * .1, w * .81, h * .1, w * .9, h * .28)
      ..cubicTo(w * .98, h * .44, w * .88, h * .66, w * .5, h * .9)
      ..close();
    canvas.drawPath(
      heart,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(Metric.heart, Colors.white, .25)!, Metric.heart],
        ).createShader(Offset.zero & size),
    );
    // Shine on the left lobe.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .24, h * .3),
        width: w * .12,
        height: h * .08,
      ),
      Paint()..color = Colors.white.withValues(alpha: .55),
    );

    // Eyes.
    const ink = Color(0xFF2B1B1F);
    for (final x in [w * .37, w * .63]) {
      canvas.drawCircle(
        Offset(x, h * .45),
        w * .075,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(x + w * .012, h * .46),
        w * .042,
        Paint()..color = ink,
      );
      canvas.drawCircle(
        Offset(x + w * .028, h * .44),
        w * .014,
        Paint()..color = Colors.white,
      );
    }

    // Cheeks.
    final blush = Paint()
      ..color = const Color(0xFFFFB3B8).withValues(alpha: .8);
    for (final x in [w * .25, w * .75]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, h * .57),
          width: w * .11,
          height: h * .06,
        ),
        blush,
      );
    }

    // Smile.
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * .5, h * .57),
        width: w * .16,
        height: h * .12,
      ),
      0.2,
      2.74,
      false,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .035
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
