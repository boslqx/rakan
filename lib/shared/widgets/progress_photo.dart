import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/workout/services/workout_log_service.dart';
import '../utils/base64_image_cache.dart';

/// A workout's progress photo.
///
/// New photos live in `users/{uid}/progressPhotos/{logId}` and are only
/// downloaded when this widget is shown (the log carries a small
/// `hasProgressPhoto` flag). Older logs stored the photo inline as
/// `progressPhotoBase64`; that is still shown directly when present.
class ProgressPhoto extends StatefulWidget {
  final Map<String, dynamic> log;
  final String? ownerUid;
  final double height;
  final double borderRadius;

  const ProgressPhoto({
    super.key,
    required this.log,
    required this.ownerUid,
    this.height = 160,
    this.borderRadius = 16,
  });

  /// Whether [log] has a photo at all — lets callers skip spacing around
  /// an empty slot.
  static bool hasPhoto(Map<String, dynamic> log) {
    final legacy = log['progressPhotoBase64'] as String?;
    return (legacy != null && legacy.isNotEmpty) ||
        log['hasProgressPhoto'] == true;
  }

  @override
  State<ProgressPhoto> createState() => _ProgressPhotoState();
}

class _ProgressPhotoState extends State<ProgressPhoto> {
  Uint8List? _bytes;
  bool _loading = false;

  /// Bumped on each resolve so a slow load for an old log can't overwrite
  /// the photo of the log this widget now shows.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ProgressPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.log['logId'] != widget.log['logId']) _resolve();
  }

  /// Sets state fields directly (no setState) for the synchronous part:
  /// this runs from initState/didUpdateWidget, and build() always follows
  /// those. Only the async load calls setState, after it completes.
  void _resolve() {
    final generation = ++_generation;
    _bytes = null;
    _loading = false;

    final legacy = widget.log['progressPhotoBase64'] as String?;
    if (legacy != null && legacy.isNotEmpty) {
      _bytes = Base64ImageCache.decode(legacy);
      return;
    }

    final uid = widget.ownerUid;
    final logId = widget.log['logId'] as String?;
    if (widget.log['hasProgressPhoto'] != true || uid == null || logId == null) {
      return;
    }

    _loading = true;
    _load(uid, logId, generation);
  }

  Future<void> _load(String uid, String logId, int generation) async {
    Uint8List? bytes;
    try {
      final photo =
          await WorkoutLogService().getProgressPhoto(uid: uid, logId: logId);
      bytes = Base64ImageCache.decode(photo);
    } catch (_) {
      bytes = null;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null && !_loading) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: _bytes == null
            ? Container(color: AppColors.surfaceContainerHigh)
            : Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
      ),
    );
  }
}
