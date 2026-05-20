import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/widgets/main_shell.dart';
import '../services/adapt_service.dart';

class WorkoutCompleteScreen extends StatefulWidget {
  final String workoutName;
  final int durationMins;
  final double totalVolume;
  final int exerciseCount;
  final String uid;
  final double avgRpe;
  final double maxRpe;
  final double completionRate;

  const WorkoutCompleteScreen({
    super.key,
    required this.workoutName,
    required this.durationMins,
    required this.totalVolume,
    required this.exerciseCount,
    required this.uid,
    required this.avgRpe,
    required this.maxRpe,
    required this.completionRate,
  });

  @override
  State<WorkoutCompleteScreen> createState() => _WorkoutCompleteScreenState();
}

class _WorkoutCompleteScreenState extends State<WorkoutCompleteScreen> {

  // Adaptation status — shown as a small banner at the bottom
  String _adaptStatus = 'loading';
  String _adaptMessage = '';

  @override
  void initState() {
    super.initState();
    _runAdaptation();
  }

  Future<void> _runAdaptation() async {
    try {
      final message = await AdaptService().predictAndAdapt(
        uid: widget.uid,
        avgRpe: widget.avgRpe,
        maxRpe: widget.maxRpe,
        sessionDuration: widget.durationMins.toDouble(),
        exercisesCount: widget.exerciseCount,
        completionRate: widget.completionRate,
      );

      if (!mounted) return;
      setState(() {
        _adaptStatus = 'done';
        // Use API message if available, fallback to local derivation
        _adaptMessage = message.isNotEmpty ? message : _buildAdaptMessage();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _adaptStatus = 'error');
    }
  }
  
  // Build a user-friendly message based on their RPE
  String _buildAdaptMessage() {
    if (widget.avgRpe > 7.5) {
      return '🔄 Next workout adjusted for recovery';
    } else if (widget.avgRpe < 4.0) {
      return '📈 Next workout intensity increased';
    } else {
      return '✅ Plan stays on track';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              // Trophy icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.primary,
                  size: 48,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'WORKOUT COMPLETE',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                widget.workoutName.toUpperCase(),
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),

              const Spacer(),

              // Stats grid
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    _buildStat('DURATION', '${widget.durationMins}', 'MIN'),
                    _buildDivider(),
                    _buildStat('VOLUME', widget.totalVolume.toStringAsFixed(0), 'KG'),
                    _buildDivider(),
                    _buildStat('EXERCISES', '${widget.exerciseCount}', 'DONE'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Adaptation status banner
              _buildAdaptBanner(),

              const Spacer(),

              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (_) => false,
                  );
                },
                child: Text(
                  'BACK TO HOME →',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptBanner() {
    if (_adaptStatus == 'loading') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Analysing your performance...',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (_adaptStatus == 'done') {
      return Text(
        _adaptMessage,
        style: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      );
    }

    // error state
    return const SizedBox.shrink();
  }

  Widget _buildStat(String label, String value, String unit) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            unit,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 9,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 48,
      color: AppColors.outlineVariant,
    );
  }
}