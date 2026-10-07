import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

import 'face_guide.dart';

/// Samples the colour of [fixedSkinPatches] from the browser camera, once per
/// video frame.
///
/// The camera plugin shows the preview on web but cannot hand frames to Dart,
/// so each frame is drawn onto a small canvas and read back from there.
class WebFrameSampler {
  /// Frames are scaled down to this width before reading. Averaging a patch
  /// gives the same mean either way, and reading back a small canvas is cheap.
  static const _width = 160;

  web.HTMLVideoElement? _video;
  web.MediaStream? _ownStream;
  web.CanvasRenderingContext2D? _ctx;
  Timer? _timer;
  bool _running = false;
  void Function(List<double>, double)? _onFrame;

  Future<void> start(
    void Function(List<double> rgb, double luma) onFrame,
  ) async {
    stop();
    _onFrame = onFrame;
    _video = _previewVideo() ?? await _openOwnStream();

    final canvas = web.HTMLCanvasElement();
    _ctx = canvas.getContext(
      '2d',
      {'willReadFrequently': true}.jsify(),
    ) as web.CanvasRenderingContext2D;
    _running = true;

    final video = _video!;
    if ((video as JSObject).has('requestVideoFrameCallback')) {
      _nextFrame();
    } else {
      // Firefox before 132: no per-frame callback, so poll at the camera rate.
      _timer = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _sample(),
      );
    }
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    // Only a stream opened here is closed; the preview's belongs to the
    // camera plugin.
    final tracks = _ownStream?.getTracks().toDart ?? const [];
    for (final track in tracks) {
      track.stop();
    }
    _ownStream = null;
    _video = null;
    _ctx = null;
  }

  /// The camera plugin's own <video>, so the frames read are exactly the ones
  /// on screen and the camera is not opened twice (iOS Safari mutes the first
  /// capture when a second one starts).
  web.HTMLVideoElement? _previewVideo() {
    final videos = web.document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      final node = videos.item(i);
      if (node == null || !node.isA<web.HTMLVideoElement>()) continue;
      final v = node as web.HTMLVideoElement;
      if (v.srcObject != null && v.videoWidth > 0) {
        return v;
      }
    }
    return null;
  }

  Future<web.HTMLVideoElement> _openOwnStream() async {
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(
          {
                'audio': false,
                'video': {
                  'facingMode': 'user',
                  'width': {'ideal': 640},
                  'height': {'ideal': 480},
                  'frameRate': {'ideal': 30},
                },
              }.jsify()
              as web.MediaStreamConstraints,
        )
        .toDart;
    _ownStream = stream;
    final video = web.HTMLVideoElement()
      ..muted = true
      ..autoplay = true
      ..playsInline = true
      ..srcObject = stream;
    await video.play().toDart;
    return video;
  }

  void _nextFrame() {
    if (!_running) return;
    _video?.requestVideoFrameCallback(
      ((JSAny? now, JSAny? metadata) {
        _sample();
        _nextFrame();
      }).toJS,
    );
  }

  void _sample() {
    final video = _video, ctx = _ctx, onFrame = _onFrame;
    if (!_running || video == null || ctx == null || onFrame == null) return;
    final vw = video.videoWidth, vh = video.videoHeight;
    if (vw == 0 || vh == 0) return;

    final cw = _width, ch = (_width * vh / vw).round();
    final canvas = ctx.canvas;
    if (canvas.width != cw || canvas.height != ch) {
      canvas
        ..width = cw
        ..height = ch;
    }
    ctx.drawImage(video, 0, 0, cw.toDouble(), ch.toDouble());
    final pixels = ctx.getImageData(0, 0, cw, ch).data.toDart;

    // The preview is cropped to fill a portrait box and then to a circle,
    // which together leave a centred square of side min²/max of the frame.
    final short = cw < ch ? cw : ch, long = cw < ch ? ch : cw;
    final side = short * short / long;
    final left = (cw - side) / 2, top = (ch - side) / 2;

    final rgb = <double>[];
    double luma = 0;
    for (final p in fixedSkinPatches) {
      final r = Rect.fromLTWH(
        left + p.left * side,
        top + p.top * side,
        p.width * side,
        p.height * side,
      );
      final x0 = r.left.floor().clamp(0, cw - 1),
          x1 = r.right.ceil().clamp(x0 + 1, cw);
      final y0 = r.top.floor().clamp(0, ch - 1),
          y1 = r.bottom.ceil().clamp(y0 + 1, ch);
      double sr = 0, sg = 0, sb = 0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        var i = (y * cw + x0) * 4;
        for (var x = x0; x < x1; x++, i += 4) {
          sr += pixels[i];
          sg += pixels[i + 1];
          sb += pixels[i + 2];
          n++;
        }
      }
      rgb.addAll([sr / n, sg / n, sb / n]);
      luma = 0.299 * sr / n + 0.587 * sg / n + 0.114 * sb / n;
    }
    onFrame(rgb, luma);
  }
}
