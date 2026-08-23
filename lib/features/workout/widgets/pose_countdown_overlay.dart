import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen countdown shown before rep-counting begins for a set.
class PoseCountdownOverlay extends StatefulWidget {
  final int seconds;
  final VoidCallback onComplete;

  const PoseCountdownOverlay({
    super.key,
    this.seconds = 7,
    required this.onComplete,
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
    return Container(
      color: Colors.black87,
      child: Center(
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                '$_remaining',
                key: ValueKey(_remaining),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 96,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Rep counting starts automatically',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}