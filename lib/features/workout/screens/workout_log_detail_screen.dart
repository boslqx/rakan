import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/workout_log_service.dart';

/// Read-only view of a single past workout: what was done, how it felt,
/// and (if attached) the progress photo from that session.
///
/// Deliberately a separate, fresh screen rather than a "view mode" bolted
/// onto WorkoutCompleteScreen — that screen is built around a workout that
/// was *just* finished (live state, the completion animation, attaching a
/// new photo). Reusing it for browsing history later would mean threading
/// a lot of "is this live or historical" conditionals through it. A plain
/// read-only screen is simpler and safer to build without risking that
/// screen's existing, working behaviour.
class WorkoutLogDetailScreen extends StatefulWidget {
  final Map<String, dynamic> log;

  const WorkoutLogDetailScreen({super.key, required this.log});

  @override
  State<WorkoutLogDetailScreen> createState() => _WorkoutLogDetailScreenState();
}

class _WorkoutLogDetailScreenState extends State<WorkoutLogDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _exerciseLogs = [];

  @override
  void initState() {
    super.initState();
    _loadExerciseLogs();
  }

  Future<void> _loadExerciseLogs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final logId = widget.log['logId'] as String?;
    if (uid == null || logId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final logs = await WorkoutLogService()
        .getExerciseLogsForWorkout(uid: uid, logId: logId);

    if (!mounted) return;
    setState(() {
      _exerciseLogs = logs;
      _isLoading = false;
    });
  }

  // Borg-scale-derived RPE colour zones, consistent with the rest of the
  // app: green <=4 (easy), amber 5-7 (moderate-hard), red >=8 (near-max).
  Color _rpeColor(int rpe) {
    if (rpe <= 4) return Colors.green;
    if (rpe <= 7) return Colors.amber;
    return AppColors.error;
  }

  String _formattedDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final workoutName = log['workoutName'] as String? ?? 'Workout';
    final completedAt = log['completedAt'] as String? ?? '';
    final durationMins = log['totalDurationMins'] as int? ?? 0;
    final totalVolume = (log['totalVolume'] as num?)?.toDouble() ?? 0;
    final photoBase64 = log['progressPhotoBase64'] as String?;

    final avgRpe = _exerciseLogs.isEmpty
        ? null
        : _exerciseLogs
                .map((e) => (e['rpeScale'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            _exerciseLogs.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: AppColors.onSurface, size: 18),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formattedDate(completedAt).toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    workoutName.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (photoBase64 != null && photoBase64.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        base64Decode(photoBase64),
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Stats row
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _statBlock('DURATION', '${durationMins}min')),
                        Expanded(
                          child: _statBlock(
                            'VOLUME',
                            totalVolume > 0 ? '${totalVolume.toStringAsFixed(0)}kg' : '—',
                          ),
                        ),
                        Expanded(
                          child: _statBlock(
                            'AVG RPE',
                            avgRpe != null ? avgRpe.toStringAsFixed(1) : '—',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Text(
                    'EXERCISES',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_exerciseLogs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No exercise details recorded for this session.',
                        style: GoogleFonts.manrope(
                            fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._exerciseLogs.map(_buildExerciseCard),
                ],
              ),
      ),
    );
  }

  Widget _statBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
      ],
    );
  }

  Widget _buildExerciseCard(Map<String, dynamic> ex) {
    final name = ex['exerciseName'] as String? ?? '';
    final muscleGroup = ex['muscleGroup'] as String? ?? '';
    final setsCompleted = ex['setsCompleted'] as int? ?? 0;
    final rpe = ex['rpeScale'] as int? ?? 5;
    final setDetails =
        (ex['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      '${muscleGroup.toUpperCase()} · $setsCompleted/${setDetails.length} SETS',
                      style: GoogleFonts.manrope(
                          fontSize: 10, letterSpacing: 1, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _rpeColor(rpe).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('RPE $rpe',
                    style: GoogleFonts.manrope(
                        fontSize: 11, fontWeight: FontWeight.w700, color: _rpeColor(rpe))),
              ),
            ],
          ),
          if (setDetails.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...setDetails.map((set) {
              final setNumber = set['setNumber'] as int? ?? 0;
              final reps = set['reps'] as int? ?? 0;
              final weightKg = (set['weightKg'] as num?)?.toDouble() ?? 0;
              final completed = set['completed'] as bool? ?? false;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      completed ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 14,
                      color: completed ? AppColors.primary : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text('SET $setNumber',
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    const Spacer(),
                    Text(
                      weightKg > 0 ? '$reps reps × ${weightKg.toStringAsFixed(1)}kg' : '$reps reps',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}