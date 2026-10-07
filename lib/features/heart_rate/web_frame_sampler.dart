// Reads the camera frames on web, where the camera plugin has no image stream.
export 'web_frame_sampler_stub.dart'
    if (dart.library.js_interop) 'web_frame_sampler_web.dart';
