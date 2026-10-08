import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../workout/services/workout_plan_service.dart';
import '../services/injury_service.dart';
import '../../workout/data/exercise_data.dart';
import 'dart:convert';
import '../models/weight_record.dart';
import '../models/workout_pr_record.dart';
import '../services/weight_record_service.dart';
import 'log_weight_screen.dart';
import 'all_records_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/plan_changes_section.dart';
import '../widgets/stats_report_tab.dart';
import '../../workout/widgets/exercise_media.dart';
import '../../../shared/utils/number_format.dart';
import 'log_injury_screen.dart';
import '../../../shared/widgets/pressable.dart';

/// Maps each broad muscle group used by `muscleRecovery` docs onto the
const Map<String, List<Muscle>> kBroadMuscleGroupToHeatmapMuscles = {
  'Chest': [Muscle.chest],
  'Back': [Muscle.upperBack, Muscle.lowerBack, Muscle.trapezius],
  'Shoulders': [Muscle.deltoids],
  'Arms': [Muscle.biceps, Muscle.triceps, Muscle.forearm],
  'Legs': [Muscle.quadriceps, Muscle.hamstring, Muscle.calves],
  'Glutes': [Muscle.gluteal],
  'Core': [Muscle.abs, Muscle.obliques],
};

const double kHeatmapHighFatigueThreshold = 0.7;
const double kHeatmapLowFatigueThreshold = 0.4;
const int kMuscleRecoveryStaleDays = 7;

const List<String> _kMonthAbbrev = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const List<String> _kMonthFullNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  // Segmented switch
  int _selectedTab = 0; // 0 = Stats Report, 1 = Recovery Map, 2 = Records

  // Records tab — Body Journey (weight timeline)
  bool _bodyJourneyLoading = true;
  List<WeightRecord> _weightRecords = []; // ascending by date
  double? _profileHeightCm;
  double? _profileWeightKgFallback; // onboarding snapshot, used only if
  // no weightRecords exist yet

  // Records tab — Workout Records (PR list)
  bool _workoutRecordsLoading = true;
  List<WorkoutPrRecord> _workoutPrRecords = []; // deduped, most-recent-first

  // Auth
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Recovery / Injury data
  bool _recoveryLoading = true;
  List<Map<String, dynamic>> _injuries = [];
  Map<String, Map<String, dynamic>> _muscleRecoveryData = {};
  BodySide _heatmapSide = BodySide.front;
  // Gender read from profile
  BodyGender _bodyGender = BodyGender.male;

  /// Injury whose status is being saved (its button shows a spinner).
  String? _updatingInjuryId;

  @override
  void initState() {
    super.initState();
    _loadRecovery();
    _loadBodyJourney();
    _loadWorkoutRecords();
  }

  // RECORDS TAB — BODY JOURNEY

  Future<void> _loadBodyJourney() async {
    if (_uid == null) return;
    setState(() => _bodyJourneyLoading = true);

    try {
      final profileSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('data')
          .get();
      final profileData = profileSnap.data();

      final records = await WeightRecordService().getAllRecordsAscending(_uid);

      if (!mounted) return;
      setState(() {
        _profileHeightCm = (profileData?['heightCm'] as num?)?.toDouble();
        _profileWeightKgFallback =
            (profileData?['weightKg'] as num?)?.toDouble();
        _weightRecords = records;
        _bodyJourneyLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen body journey error: $e');
      if (!mounted) return;
      setState(() => _bodyJourneyLoading = false);
    }
  }

  /// Current weight for the overview card: latest logged record, falling
  /// back to the onboarding snapshot only if nothing has been logged yet.
  double? get _currentWeightKg => _weightRecords.isNotEmpty
      ? _weightRecords.last.weightKg
      : _profileWeightKgFallback;

  double? get _currentBmi {
    final weight = _currentWeightKg;
    final height = _profileHeightCm;
    if (weight == null || height == null || height <= 0) return null;
    final heightM = height / 100;
    return weight / (heightM * heightM);
  }

  void _openLogWeight({WeightRecord? existingRecord}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LogWeightScreen(existingRecord: existingRecord),
      ),
    );
    if (changed == true) {
      _loadBodyJourney();
    }
  }

  void _showWeightRecordDetail(WeightRecord record) {
    final bmi = record.bmiGiven(_profileHeightCm);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(
              '${record.date.day} ${_kMonthFullNames[record.date.month - 1]} ${record.date.year}',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${record.weightKg.toStringAsFixed(1)} kg',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            if (bmi != null)
              Text(
                'BMI ${bmi.toStringAsFixed(1)}',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            if (record.progressPictureBase64 != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(record.progressPictureBase64!),
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (record.description != null &&
                record.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '"${record.description}"',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openLogWeight(existingRecord: record);
                },
                child: Text(
                  'Edit',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  // RECORDS TAB — WORKOUT RECORDS (PR list)

  /// Derives each exercise's CURRENT PR from data that already exists —
  /// does not recompute or duplicate the PR-detection that already runs
  /// at workout-completion time (prReached/prExerciseNames on each log).
  /// Dedupe-by-exercise-name, keeping only the first (= most recent)
  /// occurrence when scanning newest→oldest, is what implements "a
  /// non-PR session doesn't push an exercise back to the top."
  Future<void> _loadWorkoutRecords() async {
    if (_uid == null) return;
    setState(() => _workoutRecordsLoading = true);

    try {
      final prLogsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .where('prReached', isEqualTo: true)
          .get();

      final prLogs = prLogsSnap.docs.map((d) => d.data()).toList();
      prLogs.sort((a, b) {
        final aDate = a['completedAt'] as String? ?? '';
        final bDate = b['completedAt'] as String? ?? '';
        return bDate.compareTo(aDate); // newest first
      });

      final Map<String, WorkoutPrRecord> byExercise = {};

      for (final log in prLogs) {
        final logId = log['logId'] as String?;
        final prNames =
            (log['prExerciseNames'] as List?)?.cast<String>() ?? [];
        final completedAt =
            DateTime.tryParse(log['completedAt'] as String? ?? '');
        if (logId == null || prNames.isEmpty || completedAt == null) continue;

        // Only exercises we haven't already found a more recent PR for.
        final stillNeeded =
            prNames.where((n) => !byExercise.containsKey(n)).toList();
        if (stillNeeded.isEmpty) continue;

        final exLogsSnap = await _db
            .collection('users')
            .doc(_uid)
            .collection('workoutLogs')
            .doc(logId)
            .collection('exerciseLogs')
            .where('exerciseName', whereIn: stillNeeded)
            .get();

        for (final exDoc in exLogsSnap.docs) {
          final exData = exDoc.data();
          final exerciseName = exData['exerciseName'] as String?;
          if (exerciseName == null || byExercise.containsKey(exerciseName)) {
            continue;
          }

          final setDetails = (exData['setDetails'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          final completedSets =
              setDetails.where((s) => s['completed'] == true).toList();
          if (completedSets.isEmpty) continue;

          // The heaviest completed set is treated as "the PR performance."
          Map<String, dynamic>? bestSet;
          for (final s in completedSets) {
            final w = (s['weightKg'] as num?)?.toDouble() ?? 0;
            final bestW = (bestSet?['weightKg'] as num?)?.toDouble() ?? -1;
            if (bestSet == null || w > bestW) bestSet = s;
          }
          if (bestSet == null) continue;

          byExercise[exerciseName] = WorkoutPrRecord(
            exerciseName: exerciseName,
            weightKg: (bestSet['weightKg'] as num?)?.toDouble() ?? 0,
            reps: (bestSet['reps'] as num?)?.toInt() ?? 0,
            achievedAt: completedAt,
          );
        }
      }

      final records = byExercise.values.toList()
        ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));

      if (!mounted) return;
      setState(() {
        _workoutPrRecords = records;
        _workoutRecordsLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen workout records error: $e');
      if (!mounted) return;
      setState(() => _workoutRecordsLoading = false);
    }
  }

  Future<void> _loadRecovery() async {
    if (_uid == null) return;
    setState(() => _recoveryLoading = true);

    try {
      // Load gender from profile for heatmap body shape
      final profileSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('data')
          .get();

      final gender = profileSnap.data()?['gender'] as String? ?? 'male';
      _bodyGender = gender == 'female' ? BodyGender.female : BodyGender.male;

      // Load injuries subcollection
      final injurySnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('injuries')
          .get();

      final muscleRecoverySnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('muscleRecovery')
          .get();
      final muscleRecoveryData = {
        for (final doc in muscleRecoverySnap.docs) doc.id: doc.data(),
      };

      // If no injuries subcollection yet, seed from profile onboarding data
      if (injurySnap.docs.isEmpty) {
        final profileInjuries =
            profileSnap.data()?['injuries'] as List<dynamic>? ?? [];
        if (profileInjuries.isNotEmpty) {
          await _seedInjuriesFromProfile(profileInjuries);
          // Reload after seeding
          final reloaded = await _db
              .collection('users')
              .doc(_uid)
              .collection('injuries')
              .get();
          setState(() {
            _injuries = reloaded.docs
                .map((d) => {'id': d.id, ...d.data()})
                .toList();
            _muscleRecoveryData = muscleRecoveryData;
            _recoveryLoading = false;
          });
          return;
        }
      }

      setState(() {
        _injuries = injurySnap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _muscleRecoveryData = muscleRecoveryData;
        _recoveryLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen recovery error: $e');
      setState(() => _recoveryLoading = false);
    }
  }

  Future<void> _seedInjuriesFromProfile(List<dynamic> profileInjuries) async {
    for (final inj in profileInjuries) {
      final injMap = inj as Map<String, dynamic>;
      await _db
          .collection('users')
          .doc(_uid)
          .collection('injuries')
          .add({
        'region': injMap['region'] ?? '',
        'label': injMap['label'] ?? '',
        'isCustom': injMap['isCustom'] ?? false,
        'status': 'active',
        'loggedAt': FieldValue.serverTimestamp(),
        'recoveredAt': null,
      });
    }
  }

  // BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSegmentedSwitch(),
            // IndexedStack keeps each tab's state (and loaded data) while
            // switching between them.
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _uid == null ? const SizedBox.shrink() : StatsReportTab(uid: _uid),
                  _buildRecoveryTab(),
                  _buildRecordsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header — one line; the old two-line 32pt title took ~90px.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIOMETRIC ANALYSIS',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Performance Insights',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  static const _tabs = [
    (Icons.insights_rounded, 'STATS'),
    (Icons.healing_rounded, 'RECOVERY'),
    (Icons.emoji_events_rounded, 'RECORDS'),
  ];

  // Segmented switch
  Widget _buildSegmentedSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (int i = 0; i < _tabs.length; i++) _buildSegmentBtn(_tabs[i].$1, _tabs[i].$2, i),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(IconData icon, String label, int index) {
    final isSelected = _selectedTab == index;
    final color = isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant;
    return Expanded(
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // RECOVERY TAB
  Widget _buildRecoveryTab() {
    if (_recoveryLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecovery,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _buildReadinessCard(),
          const SizedBox(height: 14),
          _buildHeatmapCard(),
          const SizedBox(height: 14),
          _buildRecoveryStatusCard(),
          const SizedBox(height: 14),
          _buildCoachInsightCard(),
        ],
      ),
    );
  }

  // RECORDS TAB
  Widget _buildRecordsTab() {
    if (_bodyJourneyLoading || _workoutRecordsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _buildBodyOverviewRow(),
        const SizedBox(height: 16),
        _buildWeightJourneyCard(),
        const SizedBox(height: 32),
        _sectionHeader('WORKOUT RECORDS'),
        const SizedBox(height: 12),
        _buildWorkoutRecordsCard(),
        const SizedBox(height: 32),
        _sectionHeader('PLAN CHANGES'),
        const SizedBox(height: 12),
        const PlanChangesSection(),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildBodyOverviewRow() {
    final weight = _currentWeightKg;
    final height = _profileHeightCm;
    final bmi = _currentBmi;

    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: weight == null ? () => _openLogWeight() : null,
            child: _buildBodyStatChip(
              icon: Icons.monitor_weight_outlined,
              value: weight != null ? '${weight.toStringAsFixed(1)} kg' : 'Tap to add',
              label: 'Weight',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildBodyStatChip(
            icon: Icons.height_rounded,
            value: height != null ? '${height.toStringAsFixed(0)} cm' : 'Not set',
            label: 'Height',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildBodyStatChip(
            icon: Icons.calculate_outlined,
            value: bmi != null ? bmi.toStringAsFixed(1) : '--',
            label: 'BMI',
          ),
        ),
      ],
    );
  }

  /// Dedicated stat chip for the 3-column Weight/Height/BMI row. Icon sits
  /// ABOVE the value/label, not beside it — this removes the horizontal
  /// icon-vs-text width competition entirely, so it can't RenderFlex
  /// overflow no matter how long the value string is. FittedBox on the
  /// value is a second layer of defence: if a future value is still too
  /// wide for the column (e.g. a locale with longer decimal formatting),
  /// it scales the text down instead of throwing, rather than relying on
  /// ellipsis truncation alone.
  Widget _buildBodyStatChip({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightJourneyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weight Journey',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (_weightRecords.length >= 2) _buildWeightChange(),
                  ],
                ),
              ),
              Pressable(
                onTap: () => _openLogWeight(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+ Log Weight',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_weightRecords.isEmpty)
            _buildWeightJourneyEmptyState()
          else
            SizedBox(
              height: 180,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const pxPerPoint = 50.0;
                  final contentWidth = math.max(
                    constraints.maxWidth,
                    _weightRecords.length * pxPerPoint,
                  );
                  final values =
                      _weightRecords.map((r) => r.weightKg).toList();
                  final minY = values.reduce((a, b) => a < b ? a : b);
                  final maxY = values.reduce((a, b) => a > b ? a : b);
                  // Padding so the line never touches the chart edges,
                  // even when every recorded weight is identical.
                  final yPad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.2;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Start at the newest entries — the latest weight is
                    // the one that matters; older ones are a scroll back.
                    reverse: true,
                    child: SizedBox(
                      width: contentWidth,
                      child: LineChart(
                        LineChartData(
                          // Inset both ends so the edge dots and their
                          // date labels aren't clipped.
                          minX: -0.4,
                          maxX: _weightRecords.length - 0.6,
                          minY: minY - yPad,
                          maxY: maxY + yPad,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 22,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  final n = _weightRecords.length;
                                  // First, middle and last only — every
                                  // date at once ran together.
                                  if (i < 0 ||
                                      i >= n ||
                                      value != i ||
                                      !(i == 0 || i == n - 1 || (n > 4 && i == n ~/ 2))) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = _weightRecords[i].date;
                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 6,
                                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                    child: Text(
                                      '${d.day} ${_kMonthAbbrev[d.month - 1]}',
                                      style: GoogleFonts.manrope(
                                        fontSize: 9,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  AppColors.surfaceContainerHigh,
                              getTooltipItems: (spots) => spots
                                  .map((s) => LineTooltipItem(
                                        '${s.y.toStringAsFixed(1)} kg',
                                        GoogleFonts.manrope(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.onSurface,
                                        ),
                                      ))
                                  .toList(),
                            ),
                            touchCallback: (event, response) {
                              if (event is! FlTapUpEvent) return;
                              final spots = response?.lineBarSpots;
                              if (spots == null || spots.isEmpty) return;
                              final index = spots.first.x.toInt();
                              if (index < 0 || index >= _weightRecords.length) {
                                return;
                              }
                              _showWeightRecordDetail(_weightRecords[index]);
                            },
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(
                                values.length,
                                (i) => FlSpot(i.toDouble(), values[i]),
                              ),
                              isCurved: true,
                              color: AppColors.primary,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.primary.withValues(alpha: 0.08),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// "−2.4 kg since 3 JUL" — the whole journey in one line.
  Widget _buildWeightChange() {
    final first = _weightRecords.first;
    final change = _weightRecords.last.weightKg - first.weightKg;
    final text = change.abs() < 0.05
        ? 'No change'
        : '${change > 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)} kg';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$text since ${first.date.day} ${_kMonthAbbrev[first.date.month - 1]}',
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildWeightJourneyEmptyState() {
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 28,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              'No weight entries yet',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Log your first weight to start your journey.',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutRecordsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Records',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          if (_workoutPrRecords.isEmpty)
            _buildWorkoutRecordsEmptyState()
          else ...[
            ..._workoutPrRecords.take(5).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      ExerciseThumb(
                        asset: findExerciseByName(r.exerciseName)?.thumbnailAsset,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.exerciseName,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${r.achievedAt.day} ${_kMonthAbbrev[r.achievedAt.month - 1]}',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        r.weightKg > 0
                            ? '${formatKg(r.weightKg)} kg × ${r.reps}'
                            : '${r.reps} reps',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            Center(
              child: Pressable(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AllRecordsScreen(records: _workoutPrRecords),
                    ),
                  );
                },
                child: Text(
                  'View All Records →',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutRecordsEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 28,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              'No personal records yet',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Complete a workout to start earning records.',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Heatmap
  Widget _buildHeatmapCard() {
    final heatmapData = _buildMergedHeatmapData();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Front/Back toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Muscle Analysis',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildSideBtn('FRONT', BodySide.front),
                      _buildSideBtn('BACK', BodySide.back),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Heatmap
          SizedBox(
            height: 300,
            child: heatmapData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            color: AppColors.primary, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'No active injuries',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : BodyHeatmap(
                    side: _heatmapSide,
                    gender: _bodyGender,
                    data: heatmapData,
                    colors: [AppColors.primary, Colors.orange, AppColors.error],
                    bodyColor: const Color(0xFF2A2D32),
                    borderColor: AppColors.outlineVariant,
                    showBorder: true,
                  ),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildLegendDot(AppColors.error, 'Injured / High Load'),
                _buildLegendDot(const Color(0xFFE8A87C), 'Recovering / Moderate'),
                _buildLegendDot(AppColors.primary, 'Recovered / Low Load'),
                _buildLegendDot(_noDataColor, 'No Data'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBtn(String label, BodySide side) {
    final isSelected = _heatmapSide == side;
    return Pressable(
      onTap: () => setState(() => _heatmapSide = side),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 11, color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  // Injuries — log a new one, or move one on (active → recovering →
  // recovered) right from its row. Replaces the separate LOG / MARK
  // RECOVERED tiles and the extra sheet the second one opened.
  Widget _buildRecoveryStatusCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Injuries',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Pressable(
                onTap: _openLogInjuryScreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+ Log injury',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_injuries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Nothing logged. If something hurts during training, log it — your plan will work around it.',
                style: GoogleFonts.manrope(
                    fontSize: 13, height: 1.5, color: AppColors.onSurfaceVariant),
              ),
            )
          else
            ..._injuries.map((injury) => _buildInjuryRow(injury)),
        ],
      ),
    );
  }

  // Readiness — which muscle groups are fresh to train, from the same
  // muscleRecovery data (and injuries) that colour the body map below.
  static const _injuryRegionGroup = {
    'chest': 'Chest',
    'upperBack': 'Back',
    'lowerBack': 'Back',
    'neck': 'Back',
    'leftShoulder': 'Shoulders',
    'rightShoulder': 'Shoulders',
    'leftArm': 'Arms',
    'rightArm': 'Arms',
    'core': 'Core',
    'leftHip': 'Glutes',
    'rightHip': 'Glutes',
    'leftKnee': 'Legs',
    'rightKnee': 'Legs',
    'leftAnkle': 'Legs',
    'rightAnkle': 'Legs',
  };

  /// (state, days since trained) — state is one of ready, recovering,
  /// fatigued, injured, unknown.
  (String, int?) _readinessOf(String group) {
    final injured = _injuries.any((i) =>
        i['status'] != 'recovered' && _injuryRegionGroup[i['region']] == group);
    final doc = _muscleRecoveryData[group];
    final lastTrained = DateTime.tryParse(doc?['lastTrained'] as String? ?? '');
    final daysAgo = lastTrained == null
        ? null
        : DateTime.now().difference(lastTrained).inDays;
    if (injured) return ('injured', daysAgo);
    if (daysAgo == null || daysAgo > kMuscleRecoveryStaleDays) return ('unknown', daysAgo);
    final fatigue = (doc?['fatigueScore'] as num?)?.toDouble() ?? 0;
    if (fatigue >= kHeatmapHighFatigueThreshold) return ('fatigued', daysAgo);
    if (fatigue >= kHeatmapLowFatigueThreshold) return ('recovering', daysAgo);
    return ('ready', daysAgo);
  }

  Widget _buildReadinessCard() {
    const order = ['ready', 'recovering', 'fatigued', 'injured', 'unknown'];
    final groups = kBroadMuscleGroupToHeatmapMuscles.keys
        .map((g) => (g, _readinessOf(g)))
        .toList()
      ..sort((a, b) => order.indexOf(a.$2.$1).compareTo(order.indexOf(b.$2.$1)));
    final ready = groups.where((g) => g.$2.$1 == 'ready').map((g) => g.$1).toList();
    final resting = groups
        .where((g) => g.$2.$1 == 'fatigued' || g.$2.$1 == 'recovering')
        .map((g) => g.$1)
        .toList();
    final unknown = groups.every((g) => g.$2.$1 == 'unknown' || g.$2.$1 == 'injured');

    final String summary;
    if (unknown) {
      summary = 'Train this week and readiness for each muscle group shows up here.';
    } else if (resting.isEmpty) {
      summary = ready.isEmpty
          ? 'Nothing has been trained recently.'
          : 'Everything you\'ve trained recently has recovered.';
    } else {
      summary = '${resting.join(', ')} ${resting.length == 1 ? 'is' : 'are'} still recovering'
          '${ready.isEmpty ? '.' : ' — ${ready.take(3).join(', ')} ${ready.length == 1 ? 'is' : 'are'} good to go.'}';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'READINESS',
                  style: GoogleFonts.manrope(
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant),
                ),
              ),
              Text(
                '${ready.length} of ${groups.length} ready',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final (group, state) in groups) _buildReadinessChip(group, state.$1, state.$2)],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: GoogleFonts.manrope(fontSize: 12.5, height: 1.45, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessChip(String group, String state, int? daysAgo) {
    final color = switch (state) {
      'ready' => AppColors.primary,
      'recovering' => const Color(0xFFE8A87C),
      'fatigued' || 'injured' => AppColors.error,
      _ => _noDataColor,
    };
    final detail = switch (state) {
      'injured' => 'injured',
      'unknown' => daysAgo == null ? 'no data' : '${daysAgo}d ago',
      _ => daysAgo == 0 ? 'today' : '${daysAgo}d ago',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: state == 'unknown' ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            group,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: state == 'unknown' ? AppColors.onSurfaceVariant : AppColors.onSurface,
            ),
          ),
          const SizedBox(width: 5),
          Text(detail, style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildInjuryRow(Map<String, dynamic> injury) {
    final label = injury['label'] as String? ?? 'Unknown';
    final status = injury['status'] as String? ?? 'active';
    final estimatedDays = injury['estimatedRecoveryDays'] as int?;
    final estimatedLabel = injury['estimatedRecoveryLabel'] as String?;
    final loggedAt = (injury['loggedAt'] as Timestamp?)?.toDate();

    Color statusColor;
    String statusText;
    double progressValue;

    switch (status) {
      case 'active':
        statusColor = AppColors.error;
        statusText = 'Active';
        progressValue = 0.2;
        break;
      case 'recovering':
        statusColor = const Color(0xFFE8A87C);
        statusText = 'Recovering';
        progressValue = 0.6;
        break;
      case 'recovered':
        statusColor = AppColors.primary;
        statusText = 'Ready';
        progressValue = 1.0;
        break;
      default:
        statusColor = AppColors.error;
        statusText = 'Active';
        progressValue = 0.2;
    }

    // When we have an estimate, prefer elapsed-time progress over the
    // fixed per-status thirds above — capped short of 1.0 since only an
    // explicit "Mark Recovered" tap should ever show it as fully done.
    String? recoverySubtitle;
    if (status != 'recovered' && estimatedDays != null && loggedAt != null) {
      final elapsedDays = DateTime.now().difference(loggedAt).inDays;
      progressValue = (elapsedDays / estimatedDays).clamp(0.05, 0.95);
      final expected = loggedAt.add(Duration(days: estimatedDays));
      recoverySubtitle =
          'Est. recovery: $estimatedLabel · back around ${_kMonthAbbrev[expected.month - 1]} ${expected.day}';
    } else if (status != 'recovered' && estimatedLabel != null) {
      recoverySubtitle = 'Est. recovery: $estimatedLabel';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
              ),
              Text(
                statusText,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
              if (status != 'recovered') ...[
                const SizedBox(width: 10),
                _buildInjuryStepButton(
                  id: injury['id'] as String,
                  next: status == 'active' ? 'recovering' : 'recovered',
                ),
              ],
            ],
          ),
          if (recoverySubtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              recoverySubtitle,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  /// Moves an injury to its next status in place, with a spinner while
  /// the plan regenerates around it.
  Widget _buildInjuryStepButton({required String id, required String next}) {
    final busy = _updatingInjuryId == id;
    return Pressable(
      onTap: _updatingInjuryId != null
          ? null
          : () async {
              HapticFeedback.selectionClick();
              setState(() => _updatingInjuryId = id);
              try {
                await _updateInjuryStatus(id, next);
              } catch (e) {
                debugPrint('CoachScreen injury update failed: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Couldn't update that injury. Please try again.",
                          style: GoogleFonts.manrope()),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _updatingInjuryId = null);
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
              )
            : Text(
                next == 'recovering' ? 'MARK RECOVERING' : 'MARK RECOVERED',
                style: GoogleFonts.manrope(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
      ),
    );
  }

  // Coach Insight
  Widget _buildCoachInsightCard() {
    final activeInjuries =
        _injuries.where((i) => i['status'] == 'active').toList();
    final recoveringInjuries =
        _injuries.where((i) => i['status'] == 'recovering').toList();

    String insight;
    if (activeInjuries.isNotEmpty) {
      final labels = activeInjuries.map((i) => i['label']).join(', ');
      insight =
          'Active injury detected: $labels. Your next workout plan will avoid exercises that stress this area. Rest and ice if needed.';
    } else if (recoveringInjuries.isNotEmpty) {
      final labels = recoveringInjuries.map((i) => i['label']).join(', ');
      insight =
          'You are recovering from: $labels. Light mobility and rehab exercises will be prioritised in your plan.';
    } else {
      insight =
          'No active injuries. Your plan is running at full intensity. Keep monitoring how your body feels after each session.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COACH INSIGHT',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insight,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // INJURY ACTIONS
  Future<void> _openLogInjuryScreen() async {
    if (_uid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LogInjuryScreen(
          uid: _uid,
          gender: _bodyGender,
          existingInjuries: _injuries,
        ),
      ),
    );
    // Injuries are saved to Firestore as they're logged (not deferred until
    // the screen closes), so always refresh on return rather than relying
    // on a pop result — that covers the back button/gesture too.
    await _loadRecovery();
  }

  Future<void> _updateInjuryStatus(String injuryId, String newStatus) async {
    if (_uid == null) return;
    await _db
        .collection('users')
        .doc(_uid)
        .collection('injuries')
        .doc(injuryId)
        .update({
      'status': newStatus,
      if (newStatus == 'recovered')
        'recoveredAt': FieldValue.serverTimestamp(),
    });

    final plan = await WorkoutPlanService().getActivePlan(_uid);
    if (plan != null) {
      await InjuryService().triggerRegeneration(
        uid: _uid,
        planId: plan['id'] as String,
      );
    }

    await _loadRecovery(); // refresh UI
  }

  // HELPERS
  (Muscle, MuscleSide)? _regionToMuscleAndSide(String region) {
    switch (region) {
      case 'chest':
        return (Muscle.chest, MuscleSide.both);
      case 'upperBack':
        return (Muscle.upperBack, MuscleSide.both);
      case 'lowerBack':
        return (Muscle.lowerBack, MuscleSide.both);
      case 'leftShoulder':
        return (Muscle.deltoids, MuscleSide.left);
      case 'rightShoulder':
        return (Muscle.deltoids, MuscleSide.right);
      case 'leftArm':
        return (Muscle.biceps, MuscleSide.left);
      case 'rightArm':
        return (Muscle.biceps, MuscleSide.right);
      case 'core':
        return (Muscle.abs, MuscleSide.both);
      case 'leftHip':
        return (Muscle.gluteal, MuscleSide.left);
      case 'rightHip':
        return (Muscle.gluteal, MuscleSide.right);
      case 'leftKnee':
        return (Muscle.knees, MuscleSide.left);
      case 'rightKnee':
        return (Muscle.knees, MuscleSide.right);
      case 'leftAnkle':
        return (Muscle.ankles, MuscleSide.left);
      case 'rightAnkle':
        return (Muscle.ankles, MuscleSide.right);
      case 'neck':
        return (Muscle.neck, MuscleSide.both);
      default:
        return null;
    }
  }

  Map<Muscle, MuscleData> _buildMergedHeatmapData() {
    final Map<Muscle, MuscleData> result = {};

    for (final entry in kBroadMuscleGroupToHeatmapMuscles.entries) {
      final broadGroup = entry.key;
      final muscles = entry.value;
      final recoveryDoc = _muscleRecoveryData[broadGroup];

      Color fatigueColor;
      if (recoveryDoc == null) {
        fatigueColor = _noDataColor;
      } else {
        final lastTrainedStr = recoveryDoc['lastTrained'] as String?;
        final lastTrained = lastTrainedStr != null
            ? DateTime.tryParse(lastTrainedStr)
            : null;
        final isStale = lastTrained == null ||
            DateTime.now().difference(lastTrained).inDays >
                kMuscleRecoveryStaleDays;

        if (isStale) {
          fatigueColor = _noDataColor;
        } else {
          final fatigueScore =
              (recoveryDoc['fatigueScore'] as num?)?.toDouble() ?? 0.0;
          if (fatigueScore >= kHeatmapHighFatigueThreshold) {
            fatigueColor = AppColors.error;
          } else if (fatigueScore < kHeatmapLowFatigueThreshold) {
            fatigueColor = AppColors.primary;
          } else {
            fatigueColor = const Color(0xFFE8A87C);
          }
        }
      }

      for (final muscle in muscles) {
        result[muscle] = MuscleData(
          intensity: 1.0,
          color: fatigueColor,
          side: MuscleSide.both,
        );
      }
    }

    for (final injury in _injuries) {
      final status = injury['status'] as String? ?? 'active';
      if (status == 'recovered') continue;

      final region = injury['region'] as String? ?? '';
      final mapped = _regionToMuscleAndSide(region);
      if (mapped == null) continue;
      final (muscle, side) = mapped;

      final injuryColor = status == 'active'
          ? AppColors.error
          : const Color(0xFFE8A87C);

      result[muscle] = MuscleData(
        intensity: 1.0,
        color: injuryColor,
        side: side,
      );
    }

    return result;
  }

  Color get _noDataColor => AppColors.onSurfaceVariant.withValues(alpha: 0.25);
}