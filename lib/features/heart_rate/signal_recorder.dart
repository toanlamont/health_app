import 'dart:async';

/// Collects per-frame colour means for the backend to analyse.
///
/// Averaging skin pixels on the device is the first step of every rPPG method,
/// so sending the means loses nothing — and it avoids uploading video, whose
/// compression would erase a pulse worth a fraction of a percent of brightness.
class SignalRecorder {
  /// Thirty seconds rather than fifteen. A 13-second capture holds about 22
  /// beats and resolves frequency to 4.6 bpm, which is not enough to lift the
  /// pulse clear of an ordinary swallow or blink -- a real capture measured on
  /// this phone had a genuine pulse at 101 bpm sitting at only 10% of the band
  /// power. Doubling the window halves the bin width and doubles the beats.
  static const captureDuration = Duration(seconds: 30);
  static const warmup = Duration(seconds: 2);

  /// A break this long means the fingertip lifted or the face left frame. The
  /// capture restarts rather than splicing two unrelated stretches together.
  static const _maxGap = Duration(seconds: 2);

  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  DateTime? _start;
  DateTime? _lastFrameAt;
  final _times = <double>[];
  final _values = <double>[];
  int _regionCount = 1;

  int get sampleCount => _times.length;
  int get regionCount => _regionCount;

  double get sampleRate {
    if (_times.length < 2) return 0;
    final span = _times.last - _times.first;
    return span > 0 ? (_times.length - 1) / span : 0;
  }

  void start(int regionCount, [DateTime? at]) {
    _regionCount = regionCount < 1 ? 1 : regionCount;
    _start = at ?? DateTime.now();
    _lastFrameAt = null;
    _times.clear();
    _values.clear();
  }

  /// [rgb] holds R, G, B for each region in turn.
  void addFrame(List<double> rgb, [DateTime? at]) {
    final start = _start;
    if (start == null || rgb.length != _regionCount * 3) return;

    final now = at ?? DateTime.now();
    if (_lastFrameAt != null && now.difference(_lastFrameAt!) > _maxGap) {
      this.start(_regionCount, now);
      _progressController.add(0);
      return;
    }
    _lastFrameAt = now;

    final elapsed = now.difference(start);
    _progressController.add(
      (elapsed.inMicroseconds / captureDuration.inMicroseconds).clamp(0.0, 1.0),
    );

    // The opening seconds are dropped: auto-exposure is still settling and its
    // brightness ramp would dominate the signal.
    if (elapsed < warmup) return;

    _times.add(elapsed.inMicroseconds / 1e6);
    _values.addAll(rgb);
  }

  /// Red channel of the first region, for the on-screen waveform.
  List<double> recentRed([int count = 150]) {
    final stride = _regionCount * 3;
    final from = _times.length > count ? _times.length - count : 0;
    return [
      for (int i = from; i < _times.length; i++) _values[i * stride],
    ];
  }

  bool get hasEnoughData => _times.length >= 60;

  /// Seconds of signal collected so far, ignoring the discarded warm-up.
  double get spanSeconds =>
      _times.length < 2 ? 0 : _times.last - _times.first;

  Map<String, dynamic> payload(String source) => {
    'source': source,
    'times': _times,
    'region_count': _regionCount,
    'values': _values,
  };

  void dispose() {
    _progressController.close();
  }
}
