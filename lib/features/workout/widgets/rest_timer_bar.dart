import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// Rest countdown shown at the bottom of the Manual workout screen after a
/// set is ticked off. Guided mode already had a rest timer; Manual mode had
/// none, so users had to time their own rest.
///
/// Counts down from [seconds]; +30s extends it, Skip dismisses it. Vibrates
/// when rest is over, then calls [onFinished].
class RestTimerBar extends StatefulWidget {
  final int seconds;
  final String exerciseName;
  final VoidCallback onFinished;

  const RestTimerBar({
    super.key,
    required this.seconds,
    required this.exerciseName,
    required this.onFinished,
  });

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> {
  late DateTime _endsAt;
  late int _total;
  int _left = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _start(widget.seconds);
  }

  @override
  void didUpdateWidget(covariant RestTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new set was completed while resting — restart for that set.
    if (oldWidget.key != widget.key) _start(widget.seconds);
  }

  void _start(int seconds) {
    _total = seconds;
    // Wall-clock end time, so the countdown stays correct even if frames
    // are dropped or the app is briefly backgrounded.
    _endsAt = DateTime.now().add(Duration(seconds: seconds));
    _left = seconds;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    final left = _endsAt.difference(DateTime.now()).inMilliseconds;
    final secs = (left / 1000).ceil();
    if (secs <= 0) {
      _ticker?.cancel();
      HapticFeedback.heavyImpact();
      widget.onFinished();
      return;
    }
    if (secs != _left && mounted) setState(() => _left = secs);
  }

  void _extend() {
    setState(() {
      _endsAt = _endsAt.add(const Duration(seconds: 30));
      _total += 30;
      _left += 30;
    });
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _label {
    final m = _left ~/ 60;
    final s = _left % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_left / _total).clamp(0.0, 1.0) : 0.0;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: AppColors.surfaceContainerLow,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                  const Icon(Icons.timer_outlined,
                      size: 18, color: AppColors.primary),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'REST',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _label,
                    semanticsLabel: '$_left seconds of rest left',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _extend,
              child: Text('+30s',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            TextButton(
              onPressed: () {
                _ticker?.cancel();
                widget.onFinished();
              },
              child: Text('SKIP',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}
