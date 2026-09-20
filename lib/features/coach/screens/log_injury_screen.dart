import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/models/onboarding_data.dart' show BodyRegion;
import '../../onboarding/screens/steps/body_map_painter.dart'
    show regionInjuries;
import '../../workout/services/workout_plan_service.dart';
import '../services/injury_service.dart';

const List<String> _kMonthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A preset recovery-time choice shown when logging a new injury. `days`
/// drives the expected-recovery date shown here and the progress bar on
/// the Recovery Map's injury rows; null ("Not sure yet") skips both.
class _RecoveryOption {
  final String label;
  final int? days;
  const _RecoveryOption(this.label, this.days);
}

const List<_RecoveryOption> _recoveryOptions = [
  _RecoveryOption('Less than 1 week', 5),
  _RecoveryOption('1–2 weeks', 10),
  _RecoveryOption('2–4 weeks', 21),
  _RecoveryOption('1–2 months', 45),
  _RecoveryOption('2+ months', 75),
  _RecoveryOption('Not sure yet', null),
];

/// Full-screen "tap where it hurts" injury logger — same body-map
/// interaction as onboarding's Step8Safety, but each confirm writes
/// straight to Firestore (this runs post-onboarding, from Recovery Map)
/// and additionally asks for an estimated recovery time.
class LogInjuryScreen extends StatefulWidget {
  final String uid;
  final BodyGender gender;
  final List<Map<String, dynamic>> existingInjuries;

  const LogInjuryScreen({
    super.key,
    required this.uid,
    required this.gender,
    required this.existingInjuries,
  });

  @override
  State<LogInjuryScreen> createState() => _LogInjuryScreenState();
}

class _LogInjuryScreenState extends State<LogInjuryScreen> {
  bool _showFront = true;

  // Newly logged entries this session — shown as a read-only confirmation
  // list at the bottom. Already-active injuries are managed from the
  // Recovery Map's "Mark Recovered" flow instead, not from here.
  final List<Map<String, dynamic>> _sessionEntries = [];

  static final Map<String, BodyRegion> _regionByName = {
    for (final r in BodyRegion.values) r.name: r,
  };

  // Same dot layout as onboarding's Step8Safety — together the front and
  // back sets cover all 16 BodyRegion values exactly once each.
  static const List<Map<String, dynamic>> _frontDots = [
    {'region': BodyRegion.head, 'x': 0.50, 'y': 0.075},
    {'region': BodyRegion.neck, 'x': 0.50, 'y': 0.160},
    {'region': BodyRegion.leftShoulder, 'x': 0.38, 'y': 0.195},
    {'region': BodyRegion.rightShoulder, 'x': 0.62, 'y': 0.195},
    {'region': BodyRegion.chest, 'x': 0.50, 'y': 0.230},
    {'region': BodyRegion.leftArm, 'x': 0.280, 'y': 0.360},
    {'region': BodyRegion.rightArm, 'x': 0.720, 'y': 0.360},
    {'region': BodyRegion.core, 'x': 0.50, 'y': 0.340},
    {'region': BodyRegion.leftKnee, 'x': 0.43, 'y': 0.550},
    {'region': BodyRegion.rightKnee, 'x': 0.57, 'y': 0.550},
    {'region': BodyRegion.leftAnkle, 'x': 0.42, 'y': 0.740},
    {'region': BodyRegion.rightAnkle, 'x': 0.58, 'y': 0.740},
  ];

  static const List<Map<String, dynamic>> _backDots = [
    {'region': BodyRegion.head, 'x': 0.50, 'y': 0.075},
    {'region': BodyRegion.neck, 'x': 0.50, 'y': 0.145},
    {'region': BodyRegion.leftShoulder, 'x': 0.38, 'y': 0.195},
    {'region': BodyRegion.rightShoulder, 'x': 0.62, 'y': 0.195},
    {'region': BodyRegion.upperBack, 'x': 0.50, 'y': 0.235},
    {'region': BodyRegion.leftArm, 'x': 0.28, 'y': 0.360},
    {'region': BodyRegion.rightArm, 'x': 0.72, 'y': 0.360},
    {'region': BodyRegion.lowerBack, 'x': 0.50, 'y': 0.320},
    {'region': BodyRegion.leftHip, 'x': 0.46, 'y': 0.415},
    {'region': BodyRegion.rightHip, 'x': 0.54, 'y': 0.415},
    {'region': BodyRegion.leftKnee, 'x': 0.43, 'y': 0.550},
    {'region': BodyRegion.rightKnee, 'x': 0.57, 'y': 0.550},
    {'region': BodyRegion.leftAnkle, 'x': 0.42, 'y': 0.740},
    {'region': BodyRegion.rightAnkle, 'x': 0.58, 'y': 0.740},
  ];

  Set<BodyRegion> get _activeExistingRegions => widget.existingInjuries
      .where((i) => (i['status'] as String? ?? 'active') != 'recovered')
      .map((i) => _regionByName[i['region'] as String? ?? ''])
      .whereType<BodyRegion>()
      .toSet();

  Set<BodyRegion> get _sessionRegions =>
      _sessionEntries.map((e) => e['region'] as BodyRegion).toSet();

  Set<BodyRegion> get _injuredRegions => {
    ..._activeExistingRegions,
    ..._sessionRegions,
  };

  Map<Muscle, MuscleData> get _heatmapData {
    final Map<Muscle, MuscleData> data = {};
    const regionToMuscle = {
      BodyRegion.head: Muscle.head,
      BodyRegion.neck: Muscle.neck,
      BodyRegion.chest: Muscle.chest,
      BodyRegion.leftShoulder: Muscle.deltoids,
      BodyRegion.rightShoulder: Muscle.deltoids,
      BodyRegion.upperBack: Muscle.upperBack,
      BodyRegion.leftArm: Muscle.biceps,
      BodyRegion.rightArm: Muscle.triceps,
      BodyRegion.core: Muscle.abs,
      BodyRegion.lowerBack: Muscle.lowerBack,
      BodyRegion.leftHip: Muscle.adductors,
      BodyRegion.rightHip: Muscle.gluteal,
      BodyRegion.leftKnee: Muscle.quadriceps,
      BodyRegion.rightKnee: Muscle.hamstring,
      BodyRegion.leftAnkle: Muscle.calves,
      BodyRegion.rightAnkle: Muscle.ankles,
    };
    for (final region in _injuredRegions) {
      final muscle = regionToMuscle[region];
      if (muscle != null) {
        data[muscle] = MuscleData(intensity: 1.0, color: AppColors.error);
      }
    }
    return data;
  }

  String _regionLabel(BodyRegion region) {
    const labels = {
      BodyRegion.head: 'Head',
      BodyRegion.neck: 'Neck',
      BodyRegion.leftShoulder: 'Left Shoulder',
      BodyRegion.rightShoulder: 'Right Shoulder',
      BodyRegion.chest: 'Chest',
      BodyRegion.upperBack: 'Upper Back',
      BodyRegion.leftArm: 'Left Arm',
      BodyRegion.rightArm: 'Right Arm',
      BodyRegion.core: 'Core',
      BodyRegion.lowerBack: 'Lower Back',
      BodyRegion.leftHip: 'Left Hip',
      BodyRegion.rightHip: 'Right Hip',
      BodyRegion.leftKnee: 'Left Knee',
      BodyRegion.rightKnee: 'Right Knee',
      BodyRegion.leftAnkle: 'Left Ankle',
      BodyRegion.rightAnkle: 'Right Ankle',
    };
    return labels[region] ?? region.name;
  }

  /// Labels already on record for this region (existing Firestore injuries
  /// + anything logged earlier in this same session) — shown so the sheet
  /// doesn't look like it's ignoring a dot that's already lit up red.
  List<String> _existingLabelsFor(BodyRegion region) {
    final fromFirestore = widget.existingInjuries
        .where(
          (i) =>
              _regionByName[i['region'] as String? ?? ''] == region &&
              (i['status'] as String? ?? 'active') != 'recovered',
        )
        .map((i) => i['label'] as String? ?? '')
        .where((l) => l.isNotEmpty);
    final fromSession = _sessionEntries
        .where((e) => e['region'] == region)
        .expand((e) => (e['labels'] as List).cast<String>());
    return {...fromFirestore, ...fromSession}.toList();
  }

  Future<void> _showInjurySheet(BodyRegion region) async {
    final predefined = regionInjuries[region] ?? [];
    final zoneName = _regionLabel(region);
    final alreadyLogged = _existingLabelsFor(region);
    final Set<String> selectedLabels = {};
    final customController = TextEditingController();
    int? selectedRecoveryIndex;
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final canConfirm =
              !isSaving &&
              selectedRecoveryIndex != null &&
              (selectedLabels.isNotEmpty ||
                  customController.text.trim().isNotEmpty);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      zoneName.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (alreadyLogged.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Already logged here: ${alreadyLogged.join(', ')}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Select all injuries that apply',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...predefined.map((injury) {
                      final isSelected = selectedLabels.contains(injury);
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          if (isSelected) {
                            selectedLabels.remove(injury);
                          } else {
                            selectedLabels.add(injury);
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.error.withValues(alpha: 0.1)
                                : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.error
                                  : AppColors.outlineVariant,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  injury,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    color: isSelected
                                        ? AppColors.error
                                        : AppColors.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.error,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'OTHER',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: TextField(
                        controller: customController,
                        onChanged: (_) => setSheetState(() {}),
                        style: GoogleFonts.manrope(
                          color: AppColors.onSurface,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Describe your injury...',
                          hintStyle: GoogleFonts.manrope(
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'ESTIMATED RECOVERY TIME',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We'll pause exercises that target this area in your plan until you mark it recovered.",
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_recoveryOptions.length, (i) {
                        final isSelected = selectedRecoveryIndex == i;
                        return GestureDetector(
                          onTap: () =>
                              setSheetState(() => selectedRecoveryIndex = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              _recoveryOptions[i].label,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: !canConfirm
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              final option =
                                  _recoveryOptions[selectedRecoveryIndex!];
                              final labels = <String>[...selectedLabels];
                              final custom = customController.text.trim();
                              if (custom.isNotEmpty) labels.add(custom);

                              await _saveInjuries(
                                region: region,
                                labels: labels,
                                customLabel: custom,
                                option: option,
                              );

                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (!mounted) return;

                              setState(() {
                                _sessionEntries.add({
                                  'region': region,
                                  'labels': labels,
                                });
                              });

                              _showLoggedConfirmation(
                                region: region,
                                zoneName: zoneName,
                                labels: labels,
                                option: option,
                              );
                            },
                      child: isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'CONFIRM',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveInjuries({
    required BodyRegion region,
    required List<String> labels,
    required String customLabel,
    required _RecoveryOption option,
  }) async {
    final db = FirebaseFirestore.instance;
    for (final label in labels) {
      await db.collection('users').doc(widget.uid).collection('injuries').add({
        'region': region.name,
        'label': label,
        'isCustom': label == customLabel,
        'status': 'active',
        'loggedAt': FieldValue.serverTimestamp(),
        'recoveredAt': null,
        'estimatedRecoveryDays': option.days,
        'estimatedRecoveryLabel': option.label,
      });
    }

    try {
      final plan = await WorkoutPlanService().getActivePlan(widget.uid);
      if (plan != null) {
        await InjuryService().triggerRegeneration(
          uid: widget.uid,
          planId: plan['id'] as String,
        );
      }
    } catch (e) {
      debugPrint('LogInjuryScreen regeneration error: $e');
    }
  }

  void _showLoggedConfirmation({
    required BodyRegion region,
    required String zoneName,
    required List<String> labels,
    required _RecoveryOption option,
  }) {
    final willPauseExercises = kBodyRegionToMuscleGroups.containsKey(
      region.name,
    );
    final expected = option.days != null
        ? DateTime.now().add(Duration(days: option.days!))
        : null;
    final expectedStr = expected != null
        ? '${_kMonthAbbrev[expected.month - 1]} ${expected.day}'
        : null;

    final message = StringBuffer('$zoneName · ${labels.join(', ')}\n\n');
    if (willPauseExercises) {
      message.write(
        "We'll pause exercises that target this area until you mark it recovered in Recovery Map.",
      );
    } else {
      message.write('Saved to your Recovery Map.');
    }
    if (expectedStr != null) {
      message.write(
        '\n\nEstimated recovery: ${option.label} (around $expectedStr).',
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Injury Logged',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        content: Text(
          message.toString(),
          style: GoogleFonts.manrope(
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'GOT IT',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dots = _showFront ? _frontDots : _backDots;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        title: Text(
          'Log Injury',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tap the glowing dots to log where it hurts.',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(48),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToggleChip(
                            label: 'FRONT',
                            isSelected: _showFront,
                            onTap: () => setState(() => _showFront = true),
                          ),
                          _ToggleChip(
                            label: 'BACK',
                            isSelected: !_showFront,
                            onTap: () => setState(() => _showFront = false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mapWidth = constraints.maxWidth * 0.98;
                    final mapHeight = constraints.maxHeight * 1.2;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: mapWidth,
                          height: mapHeight,
                          child: BodyHeatmap(
                            side: _showFront ? BodySide.front : BodySide.back,
                            gender: widget.gender,
                            data: _heatmapData,
                            colors: [
                              AppColors.error.withValues(alpha: 0.3),
                              AppColors.error,
                            ],
                            bodyColor: AppColors.surfaceContainerHigh,
                            borderColor: AppColors.outlineVariant,
                            showBorder: true,
                          ),
                        ),
                        SizedBox(
                          width: mapWidth,
                          height: mapHeight,
                          child: Stack(
                            key: ValueKey(_showFront),
                            children: dots.map((dot) {
                              final region = dot['region'] as BodyRegion;
                              final isInjured = _injuredRegions.contains(
                                region,
                              );
                              final dx = (dot['x'] as double) * mapWidth - 8;
                              final dy = (dot['y'] as double) * mapHeight - 8;

                              return Positioned(
                                left: dx,
                                top: dy,
                                child: GestureDetector(
                                  onTap: () => _showInjurySheet(region),
                                  child: _InjuryDot(isInjured: isInjured),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_sessionEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _sessionEntries.map((entry) {
                    final region = entry['region'] as BodyRegion;
                    final labels = (entry['labels'] as List).cast<String>();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(48),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${_regionLabel(region)} · ${labels.join(', ')}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'DONE',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InjuryDot extends StatefulWidget {
  final bool isInjured;
  const _InjuryDot({required this.isInjured});

  @override
  State<_InjuryDot> createState() => _InjuryDotState();
}

class _InjuryDotState extends State<_InjuryDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isInjured
              ? AppColors.error
              : AppColors.primary.withValues(alpha: 0.9),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.7),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isInjured
                  ? AppColors.error.withValues(alpha: 0.6)
                  : AppColors.primary.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
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
