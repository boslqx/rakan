import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step4Preference extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step4Preference({super.key, required this.data, required this.onNext});

  @override
  State<Step4Preference> createState() => _Step4PreferenceState();
}

class _Step4PreferenceState extends State<Step4Preference> {
  void _saveAndContinue() {
    if (!widget.data.isStep4Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.data.workoutDays.isEmpty
                ? 'Please select at least one workout day'
                : 'Please select your session duration',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline 
          Text(
            'WORKOUT\nPREFERENCE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set your weekly schedule and session length\nso Rakan can plan around your life.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Days selector 
          _SectionLabel('TRAINING DAYS'),
          const SizedBox(height: 4),
          Text(
            'Select the days you can commit to training',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _DaySelector(
            selectedDays: widget.data.workoutDays,
            onChanged: (days) => setState(
              () => widget.data.workoutDays = days,
            ),
          ),

          const SizedBox(height: 8),

          // Selected days count
          Text(
            '${widget.data.workoutDays.length} day${widget.data.workoutDays.length == 1 ? '' : 's'} selected per week',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 32),

          // Session duration
          _SectionLabel('SESSION DURATION'),
          const SizedBox(height: 4),
          Text(
            'How long can you train per session?',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _DurationSelector(
            selected: widget.data.sessionDuration,
            onChanged: (duration) => setState(
              () => widget.data.sessionDuration = duration,
            ),
          ),

          const SizedBox(height: 16),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your schedule is used to distribute muscle groups '
                    'optimally across the week. Rest days are automatically '
                    'inserted based on recovery science.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Continue button
          ElevatedButton(
            onPressed: _saveAndContinue,
            child: Text(
              'CONTINUE >',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Section Label
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}

// Days selector
class _DaySelector extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<Set<int>> onChanged;

  const _DaySelector({
    required this.selectedDays,
    required this.onChanged,
  });

  // DateTime.monday = 1 ... DateTime.sunday = 7
  static const List<Map<String, dynamic>> _days = [
    {'label': 'M', 'full': 'Monday', 'value': DateTime.monday},
    {'label': 'T', 'full': 'Tuesday', 'value': DateTime.tuesday},
    {'label': 'W', 'full': 'Wednesday', 'value': DateTime.wednesday},
    {'label': 'T', 'full': 'Thursday', 'value': DateTime.thursday},
    {'label': 'F', 'full': 'Friday', 'value': DateTime.friday},
    {'label': 'S', 'full': 'Saturday', 'value': DateTime.saturday},
    {'label': 'S', 'full': 'Sunday', 'value': DateTime.sunday},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((day) {
        final int value = day['value'] as int;
        final bool isSelected = selectedDays.contains(value);

        return GestureDetector(
          onTap: () {
            final updated = Set<int>.from(selectedDays);
            if (isSelected) {
              updated.remove(value);
            } else {
              updated.add(value);
            }
            onChanged(updated);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.surfaceContainerLow,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.outlineVariant,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                day['label'] as String,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Session Duration Selector
class _DurationSelector extends StatelessWidget {
  final SessionDuration? selected;
  final ValueChanged<SessionDuration> onChanged;

  const _DurationSelector({
    required this.selected,
    required this.onChanged,
  });

  static const Map<SessionDuration, Map<String, String>> _content = {
    SessionDuration.thirtyMin: {
      'label': '30',
      'sub': 'min',
      'desc': 'Express',
    },
    SessionDuration.fortyFiveMin: {
      'label': '45',
      'sub': 'min',
      'desc': 'Standard',
    },
    SessionDuration.sixtyMin: {
      'label': '60',
      'sub': 'min',
      'desc': 'Optimal',
    },
    SessionDuration.ninetyPlusMin: {
      'label': '90+',
      'sub': 'min',
      'desc': 'Extended',
    },
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: SessionDuration.values.map((duration) {
        final content = _content[duration]!;
        final bool isSelected = selected == duration;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(duration),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.outlineVariant,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    content['label']!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                  Text(
                    content['sub']!,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content['desc']!,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}