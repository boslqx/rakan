import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../services/angle_calculator.dart';
import 'session_hud.dart';

/// Camera set-up lines for an exercise ("Place phone…", "Stand…"), minus
/// the leading emoji — the UI draws its own icons.
List<String> cameraSetupLines(String exerciseName) =>
    ExerciseAnalyserFactory.getInstructions(exerciseName)
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^[^A-Za-z0-9]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();

/// Share of [form]'s reps judged good form, 0–100. [form] must not be empty.
int formAccuracyPercent(List<bool> form) =>
    (form.where((ok) => ok).length * 100 / form.length).round();

/// Green for a clean set, red for a mostly-faulty one, neutral between.
Color formAccuracyColor(int percent) => percent >= 80
    ? Colors.green
    : percent >= 50
        ? AppColors.primary
        : AppColors.error;

TextStyle _label({double fontSize = 10, Color color = Colors.white54}) =>
    GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: color,
    );

/// Before a camera set: form check is on, where to put the phone and how
/// to stand.
class CameraSetupNote extends StatelessWidget {
  final String exerciseName;

  const CameraSetupNote({super.key, required this.exerciseName});

  @override
  Widget build(BuildContext context) {
    final lines = cameraSetupLines(exerciseName);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulseDot(color: Colors.greenAccent, size: 6),
              const SizedBox(width: 4),
              Text('FORM CHECK ON', style: _label(color: Colors.white70)),
              const Spacer(),
              Flexible(
                child: Text('AUTO REP COUNT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label(fontSize: 9, color: Colors.white38)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < lines.length; i++)
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
                      lines[i],
                      style: GoogleFonts.manrope(
                          fontSize: 12.5, height: 1.4, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Running count of the set's reps by form verdict — good beside bad —
/// sized to read from where the phone is propped.
class RepFormTally extends StatelessWidget {
  final int good;
  final int bad;

  const RepFormTally({super.key, required this.good, required this.bad});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$good good form, $bad bad form',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TallyChip(
              icon: Icons.check_circle_rounded,
              color: Colors.greenAccent,
              count: good,
              label: 'GOOD',
            ),
            const SizedBox(width: 8),
            _TallyChip(
              icon: Icons.cancel_rounded,
              color: Colors.redAccent,
              count: bad,
              label: 'BAD',
            ),
          ],
        ),
      ),
    );
  }
}

class _TallyChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _TallyChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                height: 1.1,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: _label(color: Colors.white60)),
        ],
      ),
    );
  }
}
