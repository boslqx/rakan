import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step1Profile extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step1Profile({super.key, required this.data, required this.onNext});

  @override
  State<Step1Profile> createState() => _Step1ProfileState();
}

class _Step1ProfileState extends State<Step1Profile> {
  final TextEditingController _nameController = TextEditingController();

  // Local state for unit toggle (will sync to data on continue)
  bool _isMetric = true;

  // Imperial controllers
  final TextEditingController _feetController = TextEditingController();
  final TextEditingController _inchesController = TextEditingController();
  final TextEditingController _lbsController = TextEditingController();

  // Metric controllers
  final TextEditingController _cmController = TextEditingController();
  final TextEditingController _kgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restore any previously entered data if user navigated back
    _nameController.text = widget.data.name ?? '';
    _isMetric = widget.data.isMetric;

    if (widget.data.heightCm != null) {
      if (_isMetric) {
        _cmController.text = widget.data.heightCm!.toStringAsFixed(0);
      } else {
        final feet = widget.data.heightCm! ~/ 30.48;
        final inches = ((widget.data.heightCm! - feet * 30.48) / 2.54).round();
        _feetController.text = feet.toString();
        _inchesController.text = inches.toString();
      }
    }
    if (widget.data.weightKg != null) {
      if (_isMetric) {
        _kgController.text = widget.data.weightKg!.toStringAsFixed(1);
      } else {
        _lbsController.text =
            (widget.data.weightKg!  * 2.20462).toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    _lbsController.dispose();
    _cmController.dispose();
    _kgController.dispose();
    super.dispose();
  }

  void _saveAndContinue() {
    // Save name
    widget.data.name = _nameController.text.trim();
    widget.data.isMetric = _isMetric;

    // Save height
    if (_isMetric) {
      final cm = double.tryParse(_cmController.text);
      if (cm != null) widget.data.heightCm = cm;
    } else {
      final feet = int.tryParse(_feetController.text) ?? 0;
      final inches = double.tryParse(_inchesController.text) ?? 0;
      widget.data.setHeightFromImperial(feet, inches);
    }

    // Save weight
    if (_isMetric) {
      final kg = double.tryParse(_kgController.text);
      if (kg != null) widget.data.weightKg = kg;
    } else {
      final lbs = double.tryParse(_lbsController.text);
      if (lbs != null) widget.data.setWeightFromLbs(lbs);
    }

    if (!widget.data.isStep1Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill in all fields',
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
            'PERSONAL\nPROFILE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us about yourself so we can build\nyour perfect training protocol.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Name
          _SectionLabel('LEGAL NAME'),
          const SizedBox(height: 8),
          _buildTextInput(
            controller: _nameController,
            hint: 'Enter your name',
          ),

          const SizedBox(height: 28),

          // Gender
          _SectionLabel('SELECT IDENTITY'),
          const SizedBox(height: 12),
          Row(
            children: [
              _GenderCard(
                icon: Icons.male_rounded,
                label: 'MALE',
                isSelected: widget.data.gender == Gender.male,
                onTap: () => setState(
                  () => widget.data.gender = Gender.male,
                ),
              ),
              const SizedBox(width: 10),
              _GenderCard(
                icon: Icons.female_rounded,
                label: 'FEMALE',
                isSelected: widget.data.gender == Gender.female,
                onTap: () => setState(
                  () => widget.data.gender = Gender.female,
                ),
              ),
              const SizedBox(width: 10),
              _GenderCard(
                icon: Icons.transgender_rounded,
                label: 'NON-\nBINARY',
                isSelected: widget.data.gender == Gender.nonBinary,
                onTap: () => setState(
                  () => widget.data.gender = Gender.nonBinary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Age
          _SectionLabel('BIOLOGICAL AGE'),
          const SizedBox(height: 12),
          _AgeSelector(
            selectedAge: widget.data.age ?? 25,
            onChanged: (age) => setState(() => widget.data.age = age),
          ),
          const SizedBox(height: 6),
          Text(
            'Used for metabolic baseline calculations.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 28),

          // Unit toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionLabel('MEASUREMENTS'),
              _UnitToggle(
                isMetric: _isMetric,
                onToggle: (val) => setState(() => _isMetric = val),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Height
          _SectionLabel('HEIGHT'),
          const SizedBox(height: 8),
          if (_isMetric)
            _buildTextInput(
              controller: _cmController,
              hint: '170',
              suffix: 'cm',
              inputType: TextInputType.number,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildTextInput(
                    controller: _feetController,
                    hint: '5',
                    suffix: 'ft',
                    inputType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextInput(
                    controller: _inchesController,
                    hint: '11',
                    suffix: 'in',
                    inputType: TextInputType.number,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Weight
          _SectionLabel('WEIGHT'),
          const SizedBox(height: 8),
          _buildTextInput(
            controller: _isMetric ? _kgController : _lbsController,
            hint: _isMetric ? '70' : '154',
            suffix: _isMetric ? 'kg' : 'lbs',
            inputType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 28),

          // Activity Level
          _SectionLabel('CURRENT ACTIVITY LEVEL'),
          const SizedBox(height: 12),
          ...ActivityLevel.values.map(
            (level) => _ActivityCard(
              level: level,
              isSelected: widget.data.activityLevel == level,
              onTap: () => setState(
                () => widget.data.activityLevel = level,
              ),
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

  // Reusable input builder
  Widget _buildTextInput({
    required TextEditingController controller,
    required String hint,
    String? suffix,
    TextInputType inputType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outlineVariant,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        inputFormatters: inputType == TextInputType.number ||
                inputType ==
                    const TextInputType.numberWithOptions(decimal: true)
            ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
            : null,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          color: AppColors.onSurface,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            color: AppColors.onSurfaceVariant.withOpacity(0.5),
          ),
          suffixText: suffix,
          suffixStyle: GoogleFonts.manrope(
            fontSize: 14,
            color: AppColors.onSurfaceVariant,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
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

// Gender Card
class _GenderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
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
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
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
  }
}

// Age Selector
class _AgeSelector extends StatefulWidget {
  final int selectedAge;
  final ValueChanged<int> onChanged;

  const _AgeSelector({
    required this.selectedAge,
    required this.onChanged,
  });

  @override
  State<_AgeSelector> createState() => _AgeSelectorState();
}

class _AgeSelectorState extends State<_AgeSelector> {
  late FixedExtentScrollController _controller;

  static const int _minAge = 13;
  static const int _maxAge = 80;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.selectedAge - _minAge,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: 48,
        perspective: 0.003,
        diameterRatio: 2.5,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          widget.onChanged(index + _minAge);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            final age = index + _minAge;
            final isSelected = age == widget.selectedAge;
            return Center(
              child: Text(
                '$age',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: isSelected ? 32 : 18,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isSelected
                      ? AppColors.onSurface
                      : AppColors.onSurfaceVariant.withOpacity(0.4),
                ),
              ),
            );
          },
          childCount: _maxAge - _minAge + 1,
        ),
      ),
    );
  }
}

// Unit Toggle
class _UnitToggle extends StatelessWidget {
  final bool isMetric;
  final ValueChanged<bool> onToggle;

  const _UnitToggle({required this.isMetric, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(
            label: 'METRIC',
            isSelected: isMetric,
            onTap: () => onToggle(true),
          ),
          _ToggleChip(
            label: 'IMPERIAL',
            isSelected: !isMetric,
            onTap: () => onToggle(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// Activity Card
class _ActivityCard extends StatelessWidget {
  final ActivityLevel level;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.level,
    required this.isSelected,
    required this.onTap,
  });

  static const Map<ActivityLevel, Map<String, String>> _content = {
    ActivityLevel.sedentary: {
      'title': 'SEDENTARY',
      'sub': 'Desk job, little to no exercise',
    },
    ActivityLevel.lightlyActive: {
      'title': 'LIGHTLY ACTIVE',
      'sub': 'Light exercise 1–2 days/week',
    },
    ActivityLevel.moderatelyActive: {
      'title': 'MODERATELY ACTIVE',
      'sub': 'Moderate exercise 3–5 days/week',
    },
    ActivityLevel.veryActive: {
      'title': 'VERY ACTIVE',
      'sub': 'Hard exercise 6–7 days/week',
    },
    ActivityLevel.athlete: {
      'title': 'ATHLETE',
      'sub': 'Intense daily training or physical job',
    },
  };

  @override
  Widget build(BuildContext context) {
    final content = _content[level]!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Selected indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: AppColors.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content['title']!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    content['sub']!,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}