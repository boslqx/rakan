import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/models/onboarding_data.dart';
import '../../onboarding/services/user_profile_service.dart';

class EditStatsScreen extends StatefulWidget {
  const EditStatsScreen({super.key});

  @override
  State<EditStatsScreen> createState() => _EditStatsScreenState();
}

class _EditStatsScreenState extends State<EditStatsScreen> {
  final _profileService = UserProfileService();

  bool _isLoading = true;
  bool _isSaving = false;

  bool _isMetric = true;
  int? _age;
  ActivityLevel? _activityLevel;

  final _ageController = TextEditingController();
  final _cmController = TextEditingController();
  final _kgController = TextEditingController();
  final _feetController = TextEditingController();
  final _inchesController = TextEditingController();
  final _lbsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _cmController.dispose();
    _kgController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    _lbsController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final profile = await _profileService.getUserProfile(uid);
    if (!mounted) return;

    final heightCm = (profile?['heightCm'] as num?)?.toDouble();
    final weightKg = (profile?['weightKg'] as num?)?.toDouble();

    setState(() {
      _isMetric = profile?['isMetric'] as bool? ?? true;
      _age = (profile?['age'] as num?)?.toInt();
      _activityLevel = _activityLevelFromName(profile?['activityLevel']);
      _ageController.text = _age?.toString() ?? '';
      _applyHeight(heightCm);
      _applyWeight(weightKg);
      _isLoading = false;
    });
  }

  void _applyHeight(double? heightCm) {
    if (heightCm == null) return;
    if (_isMetric) {
      _cmController.text = heightCm.toStringAsFixed(0);
    } else {
      final feet = heightCm ~/ 30.48;
      final inches = ((heightCm - feet * 30.48) / 2.54).round();
      _feetController.text = feet.toString();
      _inchesController.text = inches.toString();
    }
  }

  void _applyWeight(double? weightKg) {
    if (weightKg == null) return;
    if (_isMetric) {
      _kgController.text = weightKg.toStringAsFixed(1);
    } else {
      _lbsController.text = (weightKg * 2.20462).toStringAsFixed(1);
    }
  }

  void _toggleUnits(bool isMetric) {
    if (isMetric == _isMetric) return;
    // Carry over whatever the user already typed, converted to the other
    // system, instead of clearing the fields on toggle.
    final heightCm = _currentHeightCm();
    final weightKg = _currentWeightKg();
    setState(() {
      _isMetric = isMetric;
      _applyHeight(heightCm);
      _applyWeight(weightKg);
    });
  }

  ActivityLevel? _activityLevelFromName(dynamic name) {
    if (name == null) return null;
    for (final level in ActivityLevel.values) {
      if (level.name == name) return level;
    }
    return null;
  }

  double? _currentHeightCm() {
    if (_isMetric) {
      return double.tryParse(_cmController.text);
    }
    final feet = int.tryParse(_feetController.text) ?? 0;
    final inches = double.tryParse(_inchesController.text) ?? 0;
    if (feet == 0 && inches == 0) return null;
    return (feet * 30.48) + (inches * 2.54);
  }

  double? _currentWeightKg() {
    if (_isMetric) {
      return double.tryParse(_kgController.text);
    }
    final lbs = double.tryParse(_lbsController.text);
    if (lbs == null) return null;
    return lbs / 2.20462;
  }

  Future<void> _save() async {
    final age = int.tryParse(_ageController.text);
    final heightCm = _currentHeightCm();
    final weightKg = _currentWeightKg();

    if (age == null ||
        heightCm == null ||
        weightKg == null ||
        _activityLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill in all fields',
              style: GoogleFonts.manrope()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.updateStats(
        uid: uid,
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
        activityLevel: _activityLevel!,
        isMetric: _isMetric,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stats updated. This applies to your next plan reset — '
            'your current plan is unchanged.',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save stats — please try again',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        title: Text(
          'PERSONAL STATS',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'Used for metabolic baseline calculations. Changes '
                    'apply the next time your plan is regenerated — your '
                    'current active plan is not modified.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Unit toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionLabel('UNITS'),
                      _UnitToggle(isMetric: _isMetric, onToggle: _toggleUnits),
                    ],
                  ),

                  const SizedBox(height: 24),

                  _SectionLabel('AGE'),
                  const SizedBox(height: 8),
                  _buildTextInput(
                    controller: _ageController,
                    hint: '25',
                    suffix: 'yrs',
                    inputType: TextInputType.number,
                  ),

                  const SizedBox(height: 20),

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

                  _SectionLabel('WEIGHT'),
                  const SizedBox(height: 8),
                  _buildTextInput(
                    controller: _isMetric ? _kgController : _lbsController,
                    hint: _isMetric ? '70' : '154',
                    suffix: _isMetric ? 'kg' : 'lbs',
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),

                  const SizedBox(height: 24),

                  _SectionLabel('ACTIVITY LEVEL'),
                  const SizedBox(height: 12),
                  ...ActivityLevel.values.map(
                    (level) => _ActivityOption(
                      level: level,
                      isSelected: _activityLevel == level,
                      onTap: () => setState(() => _activityLevel = level),
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(
                            'SAVE CHANGES',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

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
        border: Border.all(color: AppColors.outlineVariant, width: 1),
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        inputFormatters: inputType == TextInputType.number ||
                inputType == const TextInputType.numberWithOptions(decimal: true)
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
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          suffixText: suffix,
          suffixStyle: GoogleFonts.manrope(
            fontSize: 14,
            color: AppColors.onSurfaceVariant,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

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
            color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ActivityOption extends StatelessWidget {
  final ActivityLevel level;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActivityOption({
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
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: AppColors.onPrimary)
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
