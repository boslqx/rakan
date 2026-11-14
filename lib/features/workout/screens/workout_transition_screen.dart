import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/logo_particle_painter.dart';
import 'workout_complete_screen.dart';

class WorkoutTransitionScreen extends StatefulWidget {
  // All data is passed through — this screen is just a visual bridge
  final String workoutName;
  final int durationMins;
  final double totalVolume;
  final int exerciseCount;
  final String uid;
  final double avgRpe;
  final double maxRpe;
  final double completionRate;
  final List<Map<String, dynamic>> exerciseLogs;
  final String logId;
  final List<String> prExerciseNames;

  const WorkoutTransitionScreen({
    super.key,
    required this.workoutName,
    required this.durationMins,
    required this.totalVolume,
    required this.exerciseCount,
    required this.uid,
    required this.avgRpe,
    required this.maxRpe,
    required this.completionRate,
    required this.exerciseLogs,
    required this.logId,
    this.prExerciseNames = const [],
  });

  @override
  State<WorkoutTransitionScreen> createState() =>
      _WorkoutTransitionScreenState();
}

/// Timeline (one controller, 4.3s):
///   0.0–0.4s  solid Rakan mark scales in + haptic
///   0.4–0.8s  mark dissolves into ~5k dots
///   0.8–1.9s  dots spread into two turning 3D panels
///   1.9–2.4s  dots flatten into a square ring
///   2.4–3.6s  ring rebuilds the mark, solid mark fades back in
///   3.3–3.8s  "NICE WORK." slides up, subline fades in
///   4.3s      navigate to WorkoutCompleteScreen (tap anywhere to skip)
class _WorkoutTransitionScreenState extends State<WorkoutTransitionScreen>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 4.3;
  static const _logoAsset = 'assets/images/logo_mark.png';

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4300),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });

  LogoParticles? _particles;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final particles = await LogoParticles.load(_logoAsset);
      if (!mounted) {
        particles.image.dispose();
        return;
      }
      setState(() => _particles = particles);
    } catch (_) {
      // If the logo can't be decoded, still show the text and move on.
    }
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _controller.forward();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => WorkoutCompleteScreen(
          workoutName: widget.workoutName,
          durationMins: widget.durationMins,
          totalVolume: widget.totalVolume,
          exerciseCount: widget.exerciseCount,
          uid: widget.uid,
          avgRpe: widget.avgRpe,
          maxRpe: widget.maxRpe,
          completionRate: widget.completionRate,
          exerciseLogs: widget.exerciseLogs,
          logId: widget.logId,
          prExerciseNames: widget.prExerciseNames,
        ),
        // Fade + slide up transition into complete screen
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _particles?.image.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  static double _phase(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goNext,
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * _totalSeconds;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: _particles == null
                          ? null
                          : CustomPaint(
                              painter: LogoParticlePainter(
                                particles: _particles!,
                                seconds: t,
                                color: AppColors.primary,
                              ),
                            ),
                    ),
                    const SizedBox(height: 56),
                    _buildNiceWorkText(t),
                    const SizedBox(height: 14),
                    _buildSubline(t),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNiceWorkText(double t) {
    final p = Curves.easeOut.transform(_phase(t, 3.3, 3.8));
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - p)),
        child: Text(
          'NICE WORK.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            letterSpacing: -1,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSubline(double t) {
    // Pick a motivational line based on avg RPE
    final String subline;
    if (widget.avgRpe >= 8) {
      subline = 'You left everything on the floor.';
    } else if (widget.avgRpe >= 6) {
      subline = 'Consistency builds champions.';
    } else {
      subline = 'Every rep counts. Keep showing up.';
    }

    return Opacity(
      opacity: Curves.easeIn.transform(_phase(t, 3.55, 3.95)),
      child: Text(
        subline,
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }
}
