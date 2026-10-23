import 'dart:async';
import 'package:flutter/services.dart';

/// Why the camera pipeline couldn't start. [message] is shown to the user.
class PoseStreamException implements Exception {
  final String code;
  final String message;

  const PoseStreamException(this.code, this.message);

  /// Native error codes come from PoseDetectorHandler.sendError.
  factory PoseStreamException.from(Object error) {
    final code = error is PlatformException ? error.code : 'unknown';
    return PoseStreamException(code, switch (code) {
      'model_unavailable' => "The pose tracker couldn't load.",
      'camera_unavailable' =>
        "The camera couldn't open — another app may be using it.",
      'no_frames' => "The camera didn't start.",
      _ => "The camera couldn't start.",
    });
  }

  @override
  String toString() => 'PoseStreamException($code): $message';
}

// The screen calls PoseService.stream
class PoseService {
  static const _channel = EventChannel('com.example.rakan/pose_landmarks');

  /// Native sends an event for every analysed frame — "detected: false"
  /// included — so silence this long after starting means the pipeline
  /// died without reporting an error.
  static const _firstFrameTimeout = Duration(seconds: 10);

  // Returns a stream of landmark data from Kotlin
  // exerciseType is passed to Kotlin so it can log which exercise is being detected.
  // Any failure to start arrives as a PoseStreamException error.
  static Stream<Map<String, dynamic>> getLandmarkStream(String exerciseType) {
    return Stream.multi((controller) {
      Timer? watchdog = Timer(_firstFrameTimeout, () {
        controller.addError(PoseStreamException.from(
            PlatformException(code: 'no_frames')));
      });
      final subscription = _channel.receiveBroadcastStream(exerciseType).listen(
        (event) {
          watchdog?.cancel();
          watchdog = null;
          controller.add(Map<String, dynamic>.from(event as Map));
        },
        onError: (Object error) {
          watchdog?.cancel();
          watchdog = null;
          controller.addError(PoseStreamException.from(error));
        },
        onDone: controller.close,
      );
      controller.onCancel = () {
        watchdog?.cancel();
        return subscription.cancel();
      };
    });
  }
}
