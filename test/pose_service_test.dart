import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/pose_service.dart';

const _channel = EventChannel('com.example.rakan/pose_landmarks');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Stands in for PoseDetectorHandler on the native side.
  void mockNative(MockStreamHandler? handler) => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockStreamHandler(_channel, handler);

  tearDown(() => mockNative(null));

  group('PoseService.getLandmarkStream', () {
    testWidgets('a native start-up error arrives as a PoseStreamException', (tester) async {
      mockNative(MockStreamHandler.inline(onListen: (_, events) {
        events.error(code: 'camera_unavailable', message: 'Camera in use');
      }));
      Object? error;
      final sub = PoseService.getLandmarkStream('Squat')
          .listen((_) {}, onError: (Object e) => error = e);
      await tester.pump();

      expect(error, isA<PoseStreamException>()
          .having((e) => e.code, 'code', 'camera_unavailable'));
      expect((error as PoseStreamException).message, contains('another app'));
      unawaited(sub.cancel());
      await tester.pump();
    });

    testWidgets('a pipeline that never sends a frame is reported after 10s', (tester) async {
      mockNative(MockStreamHandler.inline(onListen: (_, _) {}));
      Object? error;
      final sub = PoseService.getLandmarkStream('Squat')
          .listen((_) {}, onError: (Object e) => error = e);

      await tester.pump(const Duration(seconds: 9));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<PoseStreamException>().having((e) => e.code, 'code', 'no_frames'));
      unawaited(sub.cancel());
      await tester.pump();
    });

    testWidgets('a first frame in time disarms the watchdog', (tester) async {
      mockNative(MockStreamHandler.inline(onListen: (_, events) {
        events.success({'detected': false});
      }));
      final frames = <Map<String, dynamic>>[];
      Object? error;
      final sub = PoseService.getLandmarkStream('Squat')
          .listen(frames.add, onError: (Object e) => error = e);

      await tester.pump(const Duration(seconds: 15));
      expect(frames, [{'detected': false}]);
      expect(error, isNull);
      unawaited(sub.cancel());
      await tester.pump();
    });
  });
}
