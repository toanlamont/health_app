/// Placeholder for non-web builds; mobile reads frames from the camera plugin.
class WebFrameSampler {
  Future<void> start(void Function(List<double> rgb, double luma) onFrame) =>
      throw UnsupportedError('WebFrameSampler is web only');

  void stop() {}
}
