import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import 'signal_recorder.dart';

/// How much of the way a patch moves towards each fresh detection. At one
/// detection every fifth frame this settles in about a second.
const double roiFollowRate = 0.15;

/// Damp the frame-to-frame wobble in ML Kit's answer.
///
/// Detection runs every fifth frame and its estimate shifts by a pixel or two
/// each time, so the patch jumps in steps at 6 Hz. Across a shaded cheek even a
/// one-pixel edge shift moves the mean brightness more than the pulse does, and
/// those jumps spread energy right across the band the pulse lives in.
/// Averaging the positions over roughly a second removes the wobble without
/// letting the patch lag behind a head that is genuinely moving.
List<Rect> steadyRois(List<Rect> previous, List<Rect> fresh) {
  if (previous.length != fresh.length) return fresh;
  return [
    for (int i = 0; i < fresh.length; i++) followRect(previous[i], fresh[i]),
  ];
}

Rect followRect(Rect previous, Rect fresh) {
  // A real head movement has to be followed at once, otherwise the patch is
  // dragged across hair or background on the way to its new home.
  if ((fresh.center - previous.center).distance > fresh.width * 0.5) {
    return fresh;
  }
  return Rect.fromLTRB(
    previous.left + (fresh.left - previous.left) * roiFollowRate,
    previous.top + (fresh.top - previous.top) * roiFollowRate,
    previous.right + (fresh.right - previous.right) * roiFollowRate,
    previous.bottom + (fresh.bottom - previous.bottom) * roiFollowRate,
  );
}

/// Patches of skin the pulse is read from, in ML Kit's upright coordinates.
///
/// Anchored on the eyes rather than the face box: the box includes hair and
/// jaw, so a patch sized from it drifts onto hair or glasses, whose contrast
/// swamps the pulse the moment the head moves. Forehead and both cheeks are
/// the regions the rPPG literature uses; the backend reads all three and takes
/// the rate they agree on.
List<Rect> skinPatches(Face face) {
  final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
  final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
  final box = face.boundingBox;

  if (left == null || right == null) {
    return [
      Rect.fromLTWH(
        box.left + box.width * 0.3,
        box.top + box.height * 0.12,
        box.width * 0.4,
        box.height * 0.12,
      ),
    ];
  }

  final dx = (right.x - left.x).toDouble();
  final dy = (right.y - left.y).toDouble();
  final span = sqrt(dx * dx + dy * dy);
  if (span <= 0) return [box];

  final centre = Offset((left.x + right.x) / 2, (left.y + right.y) / 2);
  return [
    Rect.fromCenter(
      center: Offset(centre.dx, centre.dy - span * 0.55),
      width: span * 0.8,
      height: span * 0.35,
    ),
    Rect.fromCenter(
      center: Offset(left.x - span * 0.1, left.y + span * 0.55),
      width: span * 0.45,
      height: span * 0.4,
    ),
    Rect.fromCenter(
      center: Offset(right.x + span * 0.1, right.y + span * 0.55),
      width: span * 0.45,
      height: span * 0.4,
    ),
  ];
}

/// ML Kit reports face coordinates in the upright image it was handed, while
/// the pixel buffer is still in sensor orientation. This maps a rect back so
/// the sampled region actually lands on the face.
Rect mapRotatedRectToBuffer(
  Rect r,
  int rotation,
  int bufferWidth,
  int bufferHeight,
) {
  switch (rotation) {
    case 90:
      return Rect.fromLTRB(
        r.top,
        bufferHeight - r.right,
        r.bottom,
        bufferHeight - r.left,
      );
    case 180:
      return Rect.fromLTRB(
        bufferWidth - r.right,
        bufferHeight - r.bottom,
        bufferWidth - r.left,
        bufferHeight - r.top,
      );
    case 270:
      return Rect.fromLTRB(
        bufferWidth - r.bottom,
        r.left,
        bufferWidth - r.top,
        r.right,
      );
    default:
      return r;
  }
}

class MeasureScreen extends StatefulWidget {
  const MeasureScreen({super.key});

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  CameraController? _camera;
  CameraDescription? _cameraDesc;
  List<CameraDescription> _cameras = [];

  final _recorder = SignalRecorder();
  double _progress = 0;
  bool _measuring = false;
  bool _analysing = false;
  bool _done = false;

  int _bpm = 0;
  double? _snrDb;
  String? _method;
  String? _failure;
  int? _agreement;
  int? _candidates;
  Duration? _analysisTook;

  // A running estimate while the capture is still going, so the number can be
  // watched against a reference reading instead of waiting for the end.
  Timer? _liveTimer;
  bool _livePending = false;
  int _liveBpm = 0;
  int? _liveAgreement;
  int? _liveCandidates;

  /// The backend needs a few cycles before a rate means anything, and a short
  /// window resolves frequency too coarsely to be worth showing.
  static const _liveAfter = 8.0;
  static const _liveEvery = Duration(seconds: 2);

  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
    ),
  );
  bool _isDetecting = false;
  bool _faceFound = false;
  List<Rect> _faceRois = const [];
  int _frameCount = 0;
  Size? _bufferSize;
  double _lastLuma = 0;
  double _lastVariance = 0;
  bool _debug = false;

  StreamSubscription<double>? _progressSub;

  @override
  void initState() {
    super.initState();
    _progressSub = _recorder.progressStream.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p >= 1.0 && _measuring && !_analysing) _finishMeasurement();
    });
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    // The front camera: the person has to see themselves framed, and the rear
    // camera plus flash never produced a usable signal on these phones.
    _cameraDesc = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _camera = CameraController(
      _cameraDesc!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _camera!.initialize();
    if (mounted) setState(() {});
  }

  void _startMeasurement() async {
    setState(() {
      _measuring = true;
      _done = false;
      _analysing = false;
      _progress = 0;
      _bpm = 0;
      _snrDb = null;
      _method = null;
      _failure = null;
      _agreement = null;
      _candidates = null;
      _analysisTook = null;
      _faceFound = false;
      _faceRois = const [];
      _liveBpm = 0;
      _liveAgreement = null;
      _liveCandidates = null;
    });
    _frameCount = 0;
    _recorder.start(3);

    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_liveEvery, (_) => _pollLive());

    try {
      await _camera!.setFocusMode(FocusMode.locked);
    } catch (_) {}

    await _camera!.startImageStream((image) {
      if (!_measuring) return;
      _processFrame(image);
    });

    // Auto-exposure hunting shows up as slow brightness swings that look like a
    // pulse; lock it once the sensor has settled.
    Future.delayed(
      SignalRecorder.warmup - const Duration(milliseconds: 300),
      () async {
        if (!_measuring) return;
        try {
          await _camera?.setExposureMode(ExposureMode.locked);
        } catch (_) {}
      },
    );
  }

  void _processFrame(CameraImage image) {
    _frameCount++;
    _bufferSize = Size(image.width.toDouble(), image.height.toDouble());

    // Detection costs tens of milliseconds. Running it every frame would halve
    // the sample rate, so the patches are refreshed periodically and reused.
    if (!_isDetecting && (_faceRois.isEmpty || _frameCount % 5 == 0)) {
      _isDetecting = true;
      _detectFace(image).whenComplete(() => _isDetecting = false);
    }

    final rois = _faceRois;
    if (rois.length != 3) return;

    final frame = <double>[];
    for (final roi in rois) {
      final stats = _patchStats(
        image,
        roi.left.toInt(),
        roi.top.toInt(),
        roi.right.toInt(),
        roi.bottom.toInt(),
      );
      frame.addAll([stats.r, stats.g, stats.b]);
      _lastLuma = stats.luma;
      _lastVariance = stats.variance;
    }
    _recorder.addFrame(frame);
  }

  Future<void> _detectFace(CameraImage image) async {
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isEmpty) {
        _faceRois = const [];
        if (_faceFound) setState(() => _faceFound = false);
        return;
      }

      final rotation = _cameraDesc?.sensorOrientation ?? 0;
      final patches = skinPatches(faces.first);
      if (patches.length != 3) {
        _faceRois = const [];
        return;
      }
      _faceRois = steadyRois(_faceRois, [
        for (final patch in patches)
          mapRotatedRectToBuffer(patch, rotation, image.width, image.height),
      ]);
      if (!_faceFound) setState(() => _faceFound = true);
    } catch (_) {}
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_cameraDesc == null) return null;

    final rotation = InputImageRotation.values.firstWhere(
      (r) => r.rawValue == _cameraDesc!.sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );

    // ImageFormatGroup.nv21 delivers one interleaved plane; ML Kit on Android
    // only accepts nv21 or yv12 byte buffers.
    if (image.planes.length != 1) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  ({double r, double g, double b, double luma, double variance}) _patchStats(
    CameraImage image,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final startX = x0.clamp(0, image.width - 1);
    final endX = x1.clamp(startX + 1, image.width);
    final startY = y0.clamp(0, image.height - 1);
    final endY = y1.clamp(startY + 1, image.height);

    // NV21 stores interleaved V,U rows after the luma plane, at half resolution
    // in both directions.
    final chromaStart = image.height * stride;
    final hasChroma = chromaStart + stride * (image.height ~/ 2) <= bytes.length;

    double sumY = 0, sumYSquared = 0, sumR = 0, sumG = 0, sumB = 0;
    int count = 0;

    for (int y = startY; y < endY; y += 2) {
      final row = y * stride;
      final chromaRow = chromaStart + (y >> 1) * stride;
      for (int x = startX; x < endX; x += 2) {
        final i = row + x;
        if (i >= bytes.length) continue;
        final luma = bytes[i].toDouble();
        sumY += luma;
        sumYSquared += luma * luma;

        if (hasChroma) {
          final vi = chromaRow + (x >> 1) * 2;
          if (vi + 1 < bytes.length) {
            final v = bytes[vi] - 128.0;
            final u = bytes[vi + 1] - 128.0;
            sumR += luma + 1.402 * v;
            sumG += luma - 0.344 * u - 0.714 * v;
            sumB += luma + 1.772 * u;
          } else {
            sumR += luma;
            sumG += luma;
            sumB += luma;
          }
        } else {
          sumR += luma;
          sumG += luma;
          sumB += luma;
        }
        count++;
      }
    }

    if (count == 0) return (r: 0, g: 0, b: 0, luma: 0, variance: 0);
    final meanY = sumY / count;
    return (
      r: sumR / count,
      g: sumG / count,
      b: sumB / count,
      luma: meanY,
      variance: (sumYSquared / count - meanY * meanY).clamp(0, double.infinity),
    );
  }

  /// Ask the backend what the signal so far looks like, without storing it.
  Future<void> _pollLive() async {
    if (!_measuring || _livePending) return;
    if (_recorder.spanSeconds < _liveAfter) return;
    // Near the end, a poll would still be uploading the whole buffer when the
    // real analysis wants the connection, and its answer would be replaced a
    // second later anyway.
    if (_progress > 0.9) return;
    _livePending = true;
    try {
      final response = await ApiClient().dio.post(
        '/heart-rate/analyze',
        data: {..._recorder.payload('face'), 'save': false},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final body = response.data as Map<String, dynamic>;
      if (!mounted || !_measuring) return;
      setState(() {
        _liveBpm = (body['bpm'] as num?)?.toInt() ?? 0;
        _liveAgreement = (body['agreement'] as num?)?.toInt();
        _liveCandidates = (body['candidates'] as num?)?.toInt();
        // Mirrored so the debug panel shows the running figures too.
        _snrDb = (body['snr_db'] as num?)?.toDouble();
        _method = body['method'] as String?;
        _agreement = _liveAgreement;
        _candidates = _liveCandidates;
      });
    } on DioException {
      // A dropped poll is not worth interrupting the capture over; the next
      // one is two seconds away and the final analysis is what gets stored.
    } finally {
      _livePending = false;
    }
  }

  void _stopMeasurement() async {
    _liveTimer?.cancel();
    _liveTimer = null;
    setState(() => _measuring = false);
    await _releaseCamera();
  }

  void _finishMeasurement() async {
    _liveTimer?.cancel();
    _liveTimer = null;
    setState(() {
      _measuring = false;
      _analysing = true;
    });

    // Tearing the camera down is four platform round trips and stopping the
    // image stream has to dismantle the analysis pipeline, which is where the
    // wait after a capture was going. The analysis needs none of it, so it
    // starts now and the camera closes alongside it.
    final releasing = _releaseCamera();
    final started = DateTime.now();

    if (!_recorder.hasEnoughData) {
      await releasing;
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _done = true;
        _failure = 'Không thu đủ tín hiệu. Giữ mặt trong khung và ngồi yên.';
      });
      return;
    }

    try {
      final response = await ApiClient().dio.post(
        '/heart-rate/analyze',
        data: _recorder.payload('face'),
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final body = response.data as Map<String, dynamic>;
      final took = DateTime.now().difference(started);
      await releasing;
      if (!mounted) return;
      setState(() {
        _analysisTook = took;
        _analysing = false;
        _done = true;
        _bpm = (body['bpm'] as num?)?.toInt() ?? 0;
        _snrDb = (body['snr_db'] as num?)?.toDouble();
        _method = body['method'] as String?;
        _agreement = (body['agreement'] as num?)?.toInt();
        _candidates = (body['candidates'] as num?)?.toInt();
        _failure = _bpm > 0
            ? null
            : (body['message'] as String? ?? 'Không đọc được nhịp tim');
      });
    } on DioException catch (e) {
      await releasing;
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _done = true;
        _failure = e.type == DioExceptionType.connectionError
            ? 'Không kết nối được máy chủ. Điện thoại có cùng Wi-Fi không?'
            : 'Phân tích thất bại: ${e.message ?? e.type.name}';
      });
    }
  }

  Future<void> _releaseCamera() async {
    try {
      await _camera?.stopImageStream();
      await _camera?.setExposureMode(ExposureMode.auto);
      await _camera?.setFocusMode(FocusMode.auto);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Đo nhịp tim'),
        actions: [
          IconButton(
            tooltip: 'Thông tin kỹ thuật',
            onPressed: () => setState(() => _debug = !_debug),
            icon: Icon(
              Icons.bug_report_outlined,
              color: _debug ? Metric.heart : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Center(child: _buildRing(theme)),
          const SizedBox(height: 24),

          Text(
            _statusText(),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),

          if (_measuring) ...[
            const SizedBox(height: 16),
            _buildLiveReading(theme),
          ],

          if (_analysing) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],

          if (_done && _bpm > 0) ...[
            const SizedBox(height: 20),
            _buildResult(theme),
          ],

          if (_done && _bpm == 0 && _failure != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Metric.heart.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Metric.heart),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_failure!, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ],

          if (!_measuring && !_done && !_analysing) ...[
            const SizedBox(height: 24),
            _buildTips(theme),
          ],

          if (_debug) ...[
            const SizedBox(height: 16),
            _buildDebugPanel(theme),
          ],

          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: _done
                ? FilledButton.icon(
                    onPressed: () => setState(() => _done = false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Đo lại'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Metric.heart,
                      foregroundColor: Colors.white,
                    ),
                  )
                : FilledButton.icon(
                    onPressed:
                        _camera != null &&
                            _camera!.value.isInitialized &&
                            !_analysing
                        ? (_measuring ? _stopMeasurement : _startMeasurement)
                        : null,
                    icon: Icon(_measuring ? Icons.stop : Icons.favorite),
                    label: Text(_measuring ? 'Dừng' : 'Bắt đầu đo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Metric.heart,
                      foregroundColor: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The camera in a circle, ringed by the capture progress.
  Widget _buildRing(ThemeData theme) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: _measuring ? _progress : (_done ? 1 : 0),
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: Metric.heart.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(Metric.heart),
            ),
          ),
          Container(
            width: 208,
            height: 208,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _faceFound
                    ? Metric.goal
                    : theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
            child: ClipOval(child: _buildPreview(theme)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final preview = camera.value.previewSize;
    if (preview == null) return CameraPreview(camera);

    // previewSize comes back in sensor (landscape) orientation, so its sides
    // are swapped before being cropped into the portrait circle — fitting it to
    // the square directly is what squashed the image.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: preview.height,
        height: preview.width,
        child: CameraPreview(camera),
      ),
    );
  }

  Widget _buildLiveReading(ThemeData theme) {
    if (_liveBpm <= 0) {
      return Text(
        _recorder.spanSeconds < _liveAfter
            ? 'Đang thu tín hiệu...'
            : 'Đang tính...',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$_liveBpm',
              style: theme.textTheme.displaySmall?.copyWith(
                color: Metric.heart,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'bpm',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Metric.heart,
              ),
            ),
          ],
        ),
        if (_liveAgreement != null && _liveCandidates != null)
          Text(
            '$_liveAgreement/$_liveCandidates vùng da cho cùng kết quả',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildResult(ThemeData theme) {
    final zone = _zone(_bpm);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Metric.wash(Metric.heart, theme.brightness),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$_bpm',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: Metric.heart,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'bpm',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Metric.heart,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: zone.$2.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  zone.$1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: zone.$2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_agreement != null && _candidates != null)
          SectionCard(
            title: 'Độ tin cậy',
            icon: Icons.verified_outlined,
            colour: Metric.goal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (int i = 0; i < _candidates!; i++)
                      Expanded(
                        child: Container(
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i < _agreement!
                                ? Metric.goal
                                : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$_agreement trên $_candidates cách đọc cho cùng một kết quả.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _agreement == _candidates
                      ? 'Tất cả đều khớp nhau — kết quả đáng tin.'
                      : 'Chưa khớp hết. Số vẫn có thể đúng, nhưng đo lại khi '
                            'ngồi yên hơn sẽ chắc hơn.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTips(ThemeData theme) {
    return SectionCard(
      title: 'Để đo chính xác',
      icon: Icons.lightbulb_outline,
      colour: Metric.goal,
      child: Column(
        children: [
          for (final tip in const [
            (Icons.wb_sunny_outlined, 'Ngồi nơi đủ sáng, ánh sáng đều lên mặt'),
            (Icons.self_improvement, 'Ngồi yên, hạn chế nói và cử động đầu'),
            (Icons.face_outlined, 'Giữ cả khuôn mặt trong vòng tròn'),
            (Icons.timer_outlined, 'Quá trình đo mất 30 giây'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(tip.$1, size: 18, color: Metric.goal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tip.$2, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDebugPanel(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'fps ${_recorder.sampleRate.toStringAsFixed(1)} · '
              'n ${_recorder.sampleCount} · '
              'luma ${_lastLuma.toStringAsFixed(1)} · '
              'var ${_lastVariance.toStringAsFixed(0)}'
              '${_agreement != null ? ' · agree $_agreement/$_candidates' : ''}'
              '${_snrDb != null ? ' · snr ${_snrDb!.toStringAsFixed(1)}dB' : ''}'
              '${_method != null ? ' · $_method' : ''}'
              '${_analysisTook != null ? ' · ${(_analysisTook!.inMilliseconds / 1000).toStringAsFixed(1)}s' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'buf ${_bufferSize?.width.toInt()}x${_bufferSize?.height.toInt()}'
              ' rot ${_cameraDesc?.sensorOrientation} · '
              'vùng ${_faceRois.length}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: CustomPaint(
                painter: _SignalPainter(_recorder.recentRed(), Metric.heart),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    if (_analysing) return 'Đang phân tích...';
    if (_done) {
      if (_bpm > 0) return 'Đo xong';
      return 'Không đọc được nhịp tim';
    }
    if (_measuring) {
      if (!_faceFound) return 'Đưa khuôn mặt vào vòng tròn';
      final left = (SignalRecorder.captureDuration.inSeconds * (1 - _progress))
          .ceil();
      return 'Giữ yên — còn ${left}s';
    }
    return 'Ngồi nơi đủ sáng rồi bấm bắt đầu';
  }

  /// The usual resting bands for an adult.
  static (String, Color) _zone(int bpm) {
    if (bpm < 60) return ('Chậm', Metric.reminder);
    if (bpm <= 100) return ('Bình thường', Metric.goal);
    if (bpm <= 120) return ('Hơi nhanh', Metric.calories);
    return ('Nhanh', Metric.heart);
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _progressSub?.cancel();
    _camera?.dispose();
    _faceDetector.close();
    _recorder.dispose();
    super.dispose();
  }
}

/// Draws raw samples auto-scaled to the box, so a pulse shows up even though it
/// rides on a large constant brightness.
class _SignalPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _SignalPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var low = values.first;
    var high = values.first;
    for (final v in values) {
      if (v < low) low = v;
      if (v > high) high = v;
    }
    if (high - low <= 0) return;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i] - low) / (high - low) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SignalPainter old) => true;
}
