import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
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
  });

  @override
  State<WorkoutTransitionScreen> createState() =>
      _WorkoutTransitionScreenState();
}

class _WorkoutTransitionScreenState extends State<WorkoutTransitionScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────

  // Controls the trophy icon scale pulse (grows in, then pulses)
  late final AnimationController _trophyController;
  late final Animation<double> _trophyScale;

  // Controls the ring/glow expanding outward from the trophy
  late final AnimationController _ringController;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  // Controls "NICE WORK." text sliding up from below
  late final AnimationController _textController;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;

  // Controls the sub-line text fading in after "NICE WORK."
  late final AnimationController _sublineController;
  late final Animation<double> _sublineOpacity;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    // Trophy: scales from 0 → 1.15 → 1.0 (overshoot feel)
    _trophyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _trophyScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_trophyController);

    // Ring: expands from 1.0 → 2.5, fades from 0.6 → 0
    // Gives the "energy burst" effect around the trophy
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _ringScale = Tween(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
    _ringOpacity = Tween(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    // Text: slides up from 30px below, easeOut
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textSlide = Tween(
      begin: const Offset(0, 0.4), // 40% of widget height downward
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    _textOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    // Subline: simple fade in
    _sublineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _sublineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sublineController, curve: Curves.easeIn),
    );
  }

  /// Runs the animation sequence with deliberate delays between steps,
  /// then navigates to WorkoutCompleteScreen.
  ///
  /// Timeline:
  ///   0ms    → trophy scales in + haptic
  ///   200ms  → ring burst
  ///   400ms  → "NICE WORK." slides up
  ///   800ms  → subline fades in
  ///   2800ms → navigate to complete screen
  Future<void> _startSequence() async {
    // Trigger haptic immediately — physical feedback anchors the moment
    HapticFeedback.heavyImpact();

    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    _trophyController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _ringController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _sublineController.forward();

    // Wait for user to absorb the moment, then navigate
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        // Slightly longer than default for a premium feel
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => WorkoutCompleteScreen(
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
        ),
        // Fade + slide up transition into complete screen
        transitionsBuilder: (_, animation, __, child) {
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
    _trophyController.dispose();
    _ringController.dispose();
    _textController.dispose();
    _sublineController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTrophyWithRing(),
              const SizedBox(height: 40),
              _buildNiceWorkText(),
              const SizedBox(height: 14),
              _buildSubline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrophyWithRing() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ring burst behind the trophy
          AnimatedBuilder(
            animation: _ringController,
            builder: (_, __) => Transform.scale(
              scale: _ringScale.value,
              child: Opacity(
                opacity: _ringOpacity.value,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Trophy icon — scales in with overshoot
          AnimatedBuilder(
            animation: _trophyController,
            builder: (_, __) => Transform.scale(
              scale: _trophyScale.value,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.primary,
                  size: 52,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNiceWorkText() {
    return AnimatedBuilder(
      animation: _textController,
      builder: (_, __) => SlideTransition(
        position: _textSlide,
        child: FadeTransition(
          opacity: _textOpacity,
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
      ),
    );
  }

  Widget _buildSubline() {
    // Pick a motivational line based on avg RPE
    // Low RPE = pushed harder message, high RPE = recovery message
    final String subline;
    if (widget.avgRpe >= 8) {
      subline = 'You left everything on the floor.';
    } else if (widget.avgRpe >= 6) {
      subline = 'Consistency builds champions.';
    } else {
      subline = 'Every rep counts. Keep showing up.';
    }

    return FadeTransition(
      opacity: _sublineOpacity,
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