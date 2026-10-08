import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen countdown shown before rep-counting begins for a set.
///
/// The backdrop is see-through at the edges, so the camera feed and
/// skeleton stay visible while the user checks their framing. [hints] —
/// where to put the phone, how to stand — are listed under the count.
class PoseCountdownOverlay extends StatefulWidget {
  final int seconds;
  final VoidCallback onComplete;
  final List<String> hints;

  const PoseCountdownOverlay({
    super.key,
    this.seconds = 7,
    required this.onComplete,
    this.hints = const [],
  });

  @override
  State<PoseCountdownOverlay> createState() => _PoseCountdownOverlayState();
}

class _PoseCountdownOverlayState extends State<PoseCountdownOverlay> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    // Critical: if the user backs out mid-countdown, this timer must not keep firing call
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.seconds > 0 ? (_remaining / widget.seconds).clamp(0.0, 1.0) : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.9,
          colors: [
            Colors.black.withValues(alpha: 0.82),
            Colors.black.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Align(
        // Sits a little high, clear of bottom-anchored controls.
        alignment: const Alignment(0, -0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'GET IN POSITION',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox.square(
                dimension: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Text(
                          '$_remaining',
                          key: ValueKey(_remaining),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 72,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Rep counting starts automatically',
                style: GoogleFonts.manrope(fontSize: 13, color: Colors.white38),
              ),
              if (widget.hints.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < widget.hints.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                i == 0
                                    ? Icons.phone_android_rounded
                                    : Icons.accessibility_new_rounded,
                                size: 16,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.hints[i],
                                  style: GoogleFonts.manrope(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
