import 'package:flutter/services.dart';


// The screen calls PoseService.stream 
class PoseService {
  static const _channel = EventChannel('com.example.rakan/pose_landmarks');

  // Returns a stream of landmark data from Kotlin
  // exerciseType is passed to Kotlin so it can log which exercise is being detected
  static Stream<Map<String, dynamic>> getLandmarkStream(String exerciseType) {
    return _channel
        .receiveBroadcastStream(exerciseType)
        .map((event) => Map<String, dynamic>.from(event as Map));
  }
}