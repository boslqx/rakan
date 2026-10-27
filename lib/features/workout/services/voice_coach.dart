import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much a spoken cue matters. A cue cuts off a lower one still being
/// spoken and is dropped while a higher one is — so a form fault never
/// talks over a rep count.
enum CuePriority { fault, rep, announcement }

/// The text-to-speech engine, behind an interface so tests can listen in.
abstract class CueSpeaker {
  Future<void> speak(String text);
  Future<void> stop();
}

/// On-device TTS that lowers the user's music while it talks instead of
/// pausing it.
class _TtsSpeaker implements CueSpeaker {
  late final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready = _configure();

  Future<void> _configure() async {
    if (Platform.isAndroid) {
      // Android flushes the queue on each speak, so a new cue replaces the
      // one in progress by itself.
      await _tts.setAudioAttributesForNavigation();
    } else if (Platform.isIOS) {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _ready;
      // iOS queues utterances; stop first so the new cue replaces the old.
      if (Platform.isIOS) await _tts.stop();
      await _tts.speak(text, focus: true);
    } catch (e) {
      // No TTS engine on the device — the HUD still shows everything.
      debugPrint('Voice coach could not speak: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Guided mode's spoken cues: rep counts, form faults, set and rest calls.
///
/// The form analyser's message changes every frame, so faults are held to
/// a few rules before they're said: the same fault must stay on screen for
/// [holdBeforeSpeaking], and once said it waits [repeatCooldown] before it
/// can be said again.
class VoiceCoach {
  VoiceCoach({CueSpeaker? speaker, DateTime Function()? clock})
      : _speaker = speaker ?? _TtsSpeaker(),
        _now = clock ?? DateTime.now;

  static const _prefsKey = 'guided_voice_enabled';

  static const holdBeforeSpeaking = Duration(seconds: 1);
  static const repeatCooldown = Duration(seconds: 5);

  final CueSpeaker _speaker;
  final DateTime Function() _now;

  bool _enabled = true;
  bool get enabled => _enabled;

  // What is being said, by estimate — TTS engines don't reliably report
  // when a flushed utterance ends.
  CuePriority? _talking;
  DateTime _talkingUntil = DateTime(0);

  // The fault on screen, and since when.
  String? _heldFault;
  DateTime _heldSince = DateTime(0);
  final Map<String, DateTime> _faultSaidAt = {};

  /// The last rep's verdict. Analysers keep showing it between reps, but it
  /// was already said with the rep count.
  String? _repVerdict;

  /// Reads the saved mute setting. Cues are on until it says otherwise.
  Future<void> loadEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    if (!on) stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, on);
    } catch (_) {}
  }

  /// Speaks [text] unless a higher-priority cue is still being said.
  /// Returns whether it was spoken.
  bool say(String text, {CuePriority priority = CuePriority.announcement}) {
    if (!_enabled) return false;
    final spoken = speakable(text);
    if (spoken.isEmpty) return false;

    final now = _now();
    final current = now.isBefore(_talkingUntil) ? _talking : null;
    if (current != null) {
      if (priority.index < current.index) return false;
      // One fault never cuts another off mid-sentence; it waits its turn.
      if (priority == CuePriority.fault && current == CuePriority.fault) return false;
    }

    _talking = priority;
    _talkingUntil = now.add(estimatedDuration(spoken));
    unawaited(_speaker.speak(spoken));
    return true;
  }

  /// A counted rep: its number, and for a bad rep what went wrong.
  /// [verdict] is the analyser's message for the rep ("Rep 3: too shallow
  /// (85°) — sink until thighs are parallel").
  void rep(int count, {required bool good, String? verdict}) {
    _repVerdict = verdict;
    final fault = good || verdict == null
        ? ''
        : verdict.replaceFirst(RegExp(r'^Rep \d+:?\s*'), '');
    say(fault.isEmpty ? '$count' : '$count. ${_capitalised(fault)}',
        priority: CuePriority.rep);
  }

  /// Called with every camera frame: the form fault on screen, or null
  /// when the form is fine.
  void fault(String? message) {
    if (message == _repVerdict) message = null;
    final now = _now();
    if (message != _heldFault) {
      _heldFault = message;
      _heldSince = now;
      return;
    }
    if (message == null || now.difference(_heldSince) < holdBeforeSpeaking) return;
    final saidAt = _faultSaidAt[message];
    if (saidAt != null && now.difference(saidAt) < repeatCooldown) return;
    if (say(message, priority: CuePriority.fault)) _faultSaidAt[message] = now;
  }

  /// Forgets the last set's faults and verdicts.
  void resetForSet() {
    _heldFault = null;
    _repVerdict = null;
    _faultSaidAt.clear();
  }

  void stop() {
    _talking = null;
    _talkingUntil = DateTime(0);
    unawaited(_speaker.stop());
  }

  void dispose() => stop();

  /// HUD text as it should be heard: no angle readouts in brackets, dashes
  /// as pauses, "°" as "degrees".
  @visibleForTesting
  static String speakable(String text) => text
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .replaceAll('°', ' degrees')
      .replaceAll(RegExp(r'\s*—\s*'), ', ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Roughly how long [text] takes to say at a normal speaking rate.
  @visibleForTesting
  static Duration estimatedDuration(String text) {
    final words = text.split(' ').where((w) => w.isNotEmpty).length;
    return Duration(milliseconds: 300 + 360 * words);
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
