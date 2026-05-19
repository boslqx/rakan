import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../models/onboarding_data.dart';
import '../services/plan_service.dart';
import '../../home/screens/home_screen.dart';
import '../../../shared/widgets/main_shell.dart';

class PlanGenerationScreen extends StatefulWidget {
  final OnboardingData data;
  const PlanGenerationScreen({super.key, required this.data});

  @override
  State<PlanGenerationScreen> createState() => _PlanGenerationScreenState();
}

class _PlanGenerationScreenState extends State<PlanGenerationScreen>
    with TickerProviderStateMixin {

  static const List<Map<String, dynamic>> _tasks = [
    {'label': 'Analysing Biometrics',        'chip': 'ANALYSING BIOMETRICS',    'duration': 2000},
    {'label': 'Calculating Recovery Windows', 'chip': 'OPTIMISING RECOVERY',     'duration': 2000},
    {'label': 'Sequencing Exercise Protocol', 'chip': 'ALGORITHMIC SEQUENCING',  'duration': 2000},
    {'label': 'Hypertrophy Load Balancing',   'chip': 'LOAD BALANCING',          'duration': 2000},
    {'label': 'Finalising Your Plan',         'chip': 'FINALISING PLAN',         'duration': 1500},
  ];

  int _currentTaskIndex = 0;
  double _totalProgress = 0.0;
  double _taskProgress = 0.0;
  bool _isDone = false;
  final List<String> _completedChips = [];

  // Tracks if the real API call finished
  bool _apiDone = false;
  bool _animationDone = false;
  String? _error;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Run animation and API call simultaneously
    _runAnimation();
    _callGeneratePlanApi();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Runs the visual animation sequence
  Future<void> _runAnimation() async {
    final int totalDuration = _tasks.fold(
        0, (sum, task) => sum + (task['duration'] as int));
    int elapsed = 0;

    for (int i = 0; i < _tasks.length; i++) {
      if (!mounted) return;
      final int taskDuration = _tasks[i]['duration'] as int;
      const int tickInterval = 50;
      final int ticks = taskDuration ~/ tickInterval;

      setState(() {
        _currentTaskIndex = i;
        _taskProgress = 0.0;
      });

      for (int tick = 0; tick <= ticks; tick++) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: tickInterval));
        setState(() {
          _taskProgress = tick / ticks;
          _totalProgress = (elapsed + tick * tickInterval) / totalDuration;
        });
      }

      elapsed += taskDuration;
      if (mounted) {
        setState(() => _completedChips.add(_tasks[i]['chip'] as String));
      }
    }

    // Animation finished
    _animationDone = true;
    _tryNavigate();
  }

  // Calls the real FastAPI backend
  Future<void> _callGeneratePlanApi() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No user logged in');

      await PlanService().generatePlan(
        uid: uid,
        data: widget.data,
      );

      _apiDone = true;
      _tryNavigate();
    } catch (e) {
      debugPrint('Plan generation error: $e');
      // Store error but don't show it yet — wait for animation to finish
      _error = e.toString();
      _apiDone = true;
      _tryNavigate();
    }
  }

  // Only navigate when BOTH animation and API are done
  void _tryNavigate() {
    if (!_animationDone || !_apiDone) return;
    if (!mounted) return;

    setState(() => _isDone = true);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;

      if (_error != null) {
        // API failed — show error snackbar but still go to home
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Plan generation failed. Please try again from the Coach tab.',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }

      // Always navigate to MainShell regardless of API success/failure
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => const MainShell(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = _tasks[_currentTaskIndex];
    final int percentage = (_totalProgress * 100).round();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Pulsing logo
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceContainerLow,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'R',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              Text(
                _isDone
                    ? 'Your plan is ready.'
                    : 'Building your personalized\n7-day workout plan...',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 32),

              // Status chips
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _tasks.map((task) {
                  final chip = task['chip'] as String;
                  final isCompleted = _completedChips.contains(chip);
                  final isCurrent = chip == currentTask['chip'] && !_isDone;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppColors.primary.withOpacity(0.15)
                          : isCurrent
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(48),
                      border: Border.all(
                        color: isCompleted
                            ? AppColors.primary.withOpacity(0.5)
                            : isCurrent
                                ? AppColors.outlineVariant
                                : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCompleted) ...[
                          Icon(Icons.check_rounded, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          chip,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: isCompleted
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              const Spacer(flex: 2),

              // Progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('OVERALL PROGRESS',
                          style: GoogleFonts.manrope(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: AppColors.onSurfaceVariant)),
                      Text('$percentage%',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _totalProgress,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Current task card
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CURRENT TASK',
                        style: GoogleFonts.manrope(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _isDone ? 'Plan Complete' : currentTask['label'] as String,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                                height: 1.2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isDone ? '100%' : '${(_taskProgress * 100).round()}%',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _isDone ? 1.0 : _taskProgress,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}