import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/data/exercise_data.dart';
import 'dart:convert';
import '../models/weight_record.dart';
import '../models/workout_pr_record.dart';
import '../services/weight_record_service.dart';
import 'log_weight_screen.dart';
import 'all_records_screen.dart';
import '../../onboarding/models/onboarding_data.dart';
import '../../onboarding/screens/plan_generation_screen.dart';
import 'package:fl_chart/fl_chart.dart';

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

/// One bucket in the Training Trends carousel (a day or a week, depending
/// on the selected range). `completedAt` on workoutLogs is the only date
/// source we trust — see WorkoutLogService.saveWorkoutLog.
class _TrendPoint {
  final DateTime bucketStart;
  final String label;
  int workoutCount;
  double totalVolume;
  double totalDurationMins;

  _TrendPoint({
    required this.bucketStart,
    required this.label,
    this.workoutCount = 0,
    this.totalVolume = 0.0,
    this.totalDurationMins = 0.0,
  });
}

const List<String> _kMonthAbbrev = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const List<String> _kMonthFullNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Fixed axis order for the Muscle Focus radar chart. These are the app's
/// existing 7 broad groups (ExerciseData.muscleGroup is already one of
/// these strings directly — there is no granular Biceps/Triceps/Quads
/// data to split out, so the radar deliberately uses 7 axes, not 10).
const List<String> _kMuscleFocusGroups = [
  MuscleGroups.chest,
  MuscleGroups.back,
  MuscleGroups.shoulders,
  MuscleGroups.arms,
  MuscleGroups.legs,
  MuscleGroups.glutes,
  MuscleGroups.core,
];

/// One radar axis's worth of data for the Muscle Focus section.
class _MuscleFocusStat {
  final String group;
  final double volume;
  final int sets;
  final int exerciseCount;
  final double percentOfTotal; // 0..1, share of this period's total volume
  final double normalized; // 0..1, this group's volume / the max group's

  _MuscleFocusStat({
    required this.group,
    required this.volume,
    required this.sets,
    required this.exerciseCount,
    required this.percentOfTotal,
    required this.normalized,
  });
}

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

  // Stats data
  bool _statsLoading = true;
  List<Map<String, dynamic>> _recentLogs = [];
  Map<String, int> _muscleFrequency = {}; // muscleGroup → times trained
  int _workoutsThisWeek = 0;
  int _plannedThisWeek = 0;

  // Adherence (4-week)
  bool _adherenceLoading = true;
  int _completedLast4Weeks = 0;
  int _targetLast4Weeks = 0;

  // Training Trends (Workout / Volume / Duration carousel)
  bool _trendsLoading = true;
  // Raw logs fetched once; covers up to 3 months so range-switching never
  // re-hits Firestore, it just re-buckets this list in Dart.
  List<Map<String, dynamic>> _trendLogs = [];
  int _trendsRangeIndex = 1; // 0 = Week, 1 = Month (default), 2 = 3 Months
  static const List<String> _trendsRangeLabels = ['WEEK', 'MONTH', '3 MONTHS'];
  int _trendsCarouselPage = 0; // 0 = Workouts, 1 = Volume, 2 = Duration
  final PageController _trendsPageController = PageController();
  List<_TrendPoint> _trendPoints = [];

  // Monthly Overview (streak + workout-total + calendar)
  // Derived from _trendLogs — no separate Firestore fetch. Known
  // limitation: since _trendLogs is capped at 500 docs, a user with more
  // than ~500 lifetime logs could see an inaccurate total/calendar for
  // very old months, or a streak longer than what's cached. Documented
  // rather than silently patched, consistent with the Phase 13
  // 30-log-scan limitation already accepted elsewhere in this app.
  DateTime _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Set<DateTime> _workoutDates = {};
  int _currentStreak = 0;
  int _workoutsInDisplayedMonth = 0;

  // Muscle Focus (radar chart) — reads the SAME _trendsRangeIndex filter
  // as Trends, per spec. Requires a fresh exerciseLogs subcollection read
  // per log every time the range changes (not cached), since _trendLogs
  // only holds top-level log fields.
  bool _muscleFocusLoading = true;
  List<_MuscleFocusStat> _muscleFocusStats = [];
  String? _selectedMuscleFocusGroup;

  // Exercise progression
  List<String> _loggedExerciseNames = [];
  String? _selectedExercise;
  bool _progressionLoading = false;
  List<Map<String, dynamic>> _progressionData = []; // [{date, maxWeight, rpe}]

  // 0 = 7 days, 1 = 30 days, 2 = 90 days, 3 = all time
  int _progressionRangeIndex = 1; // default: 30 days
  static const List<int?> _progressionRangeDays = [7, 30, 90, null];
  static const List<String> _progressionRangeLabels = ['7D', '30D', '90D', 'ALL'];

  // Recovery / Injury data
  bool _recoveryLoading = true;
  List<Map<String, dynamic>> _injuries = [];
  Map<String, Map<String, dynamic>> _muscleRecoveryData = {};
  BodySide _heatmapSide = BodySide.front;
  // Gender read from profile
  BodyGender _bodyGender = BodyGender.male;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadRecovery();
    _loadAdherence();
    _loadLoggedExerciseNames();
    _loadTrends();
    _loadBodyJourney();
    _loadWorkoutRecords();
  }

  @override
  void dispose() {
    _trendsPageController.dispose();
    super.dispose();
  }

  // DATA LOADING
  Future<void> _loadAdherence() async {
    if (_uid == null) return;
    setState(() => _adherenceLoading = true);

    try {
      final windowStart = DateTime.now().subtract(const Duration(days: 28));

      // Count completed logs in the last 28 days
      final logsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .get();

      int completed = 0;
      for (final doc in logsSnap.docs) {
        final data = doc.data();
        final isCompleted = data['isCompleted'] as bool? ?? false;
        if (!isCompleted) continue;
        final completedStr = data['completedAt'] as String? ?? '';
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;
        if (completedAt.isAfter(windowStart)) completed++;
      }

      // Target: current plan's workout-day count × 4
      final plan = await WorkoutPlanService().getActivePlan(_uid!);
      int workoutDaysInPlan = 0;
      if (plan != null) {
        final days = plan['days'] as List<dynamic>? ?? [];
        for (final day in days) {
          final dayType = day['dayType'] as String? ?? '';
          if (dayType == 'workout') workoutDaysInPlan++;
        }
      }

      setState(() {
        _completedLast4Weeks = completed;
        _targetLast4Weeks = workoutDaysInPlan * 4;
        _adherenceLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen adherence error: $e');
      setState(() => _adherenceLoading = false);
    }
  }

  Future<void> _loadLoggedExerciseNames() async {
    if (_uid == null) return;

    try {
      final logsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .get();

      final Set<String> names = {};
      for (final logDoc in logsSnap.docs) {
        final exLogs = await logDoc.reference.collection('exerciseLogs').get();
        for (final ex in exLogs.docs) {
          final name = ex.data()['exerciseName'] as String?;
          if (name != null && name.isNotEmpty) names.add(name);
        }
      }

      final sortedNames = names.toList()..sort();
      if (!mounted) return;
      setState(() {
        _loggedExerciseNames = sortedNames;
        if (sortedNames.isNotEmpty) {
          _selectedExercise = sortedNames.first;
          _loadExerciseProgression(sortedNames.first);
        }
      });
    } catch (e) {
      debugPrint('CoachScreen exercise names error: $e');
    }
  }

  Future<void> _loadExerciseProgression(String exerciseName) async {
    if (_uid == null) return;
    setState(() => _progressionLoading = true);

    try {
      final rangeDays = _progressionRangeDays[_progressionRangeIndex];
      final windowStart = rangeDays != null
          ? DateTime.now().subtract(Duration(days: rangeDays))
          : null;

      final logsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .get();

      final List<Map<String, dynamic>> points = [];

      for (final logDoc in logsSnap.docs) {
        final logData = logDoc.data();
        final completedStr = logData['completedAt'] as String? ?? '';
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;

        // Skip logs outside the selected window (all-time skips this check)
        if (windowStart != null && completedAt.isBefore(windowStart)) continue;

        final exLogs = await logDoc.reference
            .collection('exerciseLogs')
            .where('exerciseName', isEqualTo: exerciseName)
            .get();

        for (final ex in exLogs.docs) {
          final data = ex.data();
          final setDetails = data['setDetails'] as List<dynamic>? ?? [];
          double maxWeight = 0.0;
          for (final s in setDetails) {
            final w = (s['weightKg'] as num?)?.toDouble() ?? 0.0;
            if (w > maxWeight) maxWeight = w;
          }
          final rpe = (data['rpeScale'] as num?)?.toDouble() ?? 0.0;

          points.add({
            'date': completedAt,
            'maxWeight': maxWeight,
            'rpe': rpe,
          });
        }
      }

      points.sort((a, b) =>
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      if (!mounted) return;
      setState(() {
        _progressionData = points;
        _progressionLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen progression error: $e');
      setState(() => _progressionLoading = false);
    }
  }

  void _onRangeChanged(int index) {
    setState(() => _progressionRangeIndex = index);
    if (_selectedExercise != null) {
      _loadExerciseProgression(_selectedExercise!);
    }
  }

  // TRAINING TRENDS (Workout / Volume / Duration carousel)

  /// Fetches raw logs ONCE (covers up to 3 months). Range switching after
  /// this never touches Firestore again — it just re-buckets in Dart.
  Future<void> _loadTrends() async {
    if (_uid == null) return;
    setState(() => _trendsLoading = true);

    try {
      // 500 is generous headroom, not a magic number: even at 5 sessions/
      // week, 3 months is ~65 logs.
      final logs = await WorkoutLogService().getRecentLogs(_uid!, limit: 500);
      _trendLogs = logs;
      _trendPoints = _buildTrendPoints(_trendLogs, _trendsRangeIndex);
      _recomputeMonthlyOverview();
      if (!mounted) return;
      setState(() => _trendsLoading = false);
      _loadMuscleFocus(); // separate loading state; doesn't block Trends UI
    } catch (e) {
      debugPrint('CoachScreen trends error: $e');
      if (!mounted) return;
      setState(() => _trendsLoading = false);
    }
  }

  void _onTrendsRangeChanged(int index) {
    setState(() {
      _trendsRangeIndex = index;
      _trendPoints = _buildTrendPoints(_trendLogs, _trendsRangeIndex);
    });
    _loadMuscleFocus(); // window changed → re-fetch exerciseLogs for it
  }

  /// Same window-start math as _buildTrendPoints's earliest bucket, kept
  /// as its own small function rather than reusing _trendPoints directly
  /// — Muscle Focus needs one window boundary, not a bucketed series, and
  /// duplicating 3 lines of date math here avoids coupling two features
  /// that only coincidentally share a filter control.
  DateTime _muscleFocusWindowStart(int rangeIndex) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (rangeIndex == 0) {
      return today.subtract(Duration(days: today.weekday - 1)); // this week
    } else if (rangeIndex == 1) {
      return today.subtract(const Duration(days: 29)); // last 30 days
    } else {
      final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
      return thisWeekStart.subtract(const Duration(days: 7 * 12)); // 13 weeks
    }
  }

  /// Fetches exerciseLogs subcollections for every workoutLog within the
  /// selected window, sums volume/sets/exercise-count per PRIMARY
  /// muscleGroup only (per your steer), using the identical per-set
  /// volume formula already established in
  /// WorkoutLogService.updateMuscleRecovery (weightKg > 0 ? reps * weightKg
  /// : reps — bodyweight sets count reps only). Not reusing that method
  /// directly since it writes a fixed 7-day Firestore doc; this needs an
  /// arbitrary window computed in memory.
  Future<void> _loadMuscleFocus() async {
    if (_uid == null) return;
    setState(() => _muscleFocusLoading = true);

    try {
      final windowStart = _muscleFocusWindowStart(_trendsRangeIndex);
      final logsInWindow = _trendLogs.where((log) {
        final completedAt =
            DateTime.tryParse(log['completedAt'] as String? ?? '');
        return completedAt != null && !completedAt.isBefore(windowStart);
      }).toList();

      final Map<String, double> volumeByGroup = {};
      final Map<String, int> setsByGroup = {};
      final Map<String, Set<String>> exercisesByGroup = {};

      for (final log in logsInWindow) {
        final logId = log['logId'] as String?;
        if (logId == null) continue;

        final exLogsSnap = await _db
            .collection('users')
            .doc(_uid)
            .collection('workoutLogs')
            .doc(logId)
            .collection('exerciseLogs')
            .get();

        for (final exDoc in exLogsSnap.docs) {
          final exData = exDoc.data();
          final group = exData['muscleGroup'] as String?;
          if (group == null || !_kMuscleFocusGroups.contains(group)) continue;

          final exerciseName = exData['exerciseName'] as String? ?? '';
          final setDetails =
              (exData['setDetails'] as List?)?.cast<Map<String, dynamic>>() ??
                  [];
          final completedSets =
              setDetails.where((s) => s['completed'] == true).toList();
          if (completedSets.isEmpty) continue;

          final volume = completedSets.fold<double>(0.0, (sum, s) {
            final reps = (s['reps'] as num?)?.toDouble() ?? 0;
            final weightKg = (s['weightKg'] as num?)?.toDouble() ?? 0;
            return sum + (weightKg > 0 ? reps * weightKg : reps);
          });

          volumeByGroup[group] = (volumeByGroup[group] ?? 0) + volume;
          setsByGroup[group] = (setsByGroup[group] ?? 0) + completedSets.length;
          exercisesByGroup.putIfAbsent(group, () => {}).add(exerciseName);
        }
      }

      final totalVolume = volumeByGroup.values.fold(0.0, (a, b) => a + b);
      final maxVolume = volumeByGroup.values.isEmpty
          ? 0.0
          : volumeByGroup.values.reduce((a, b) => a > b ? a : b);

      final stats = _kMuscleFocusGroups.map((group) {
        final volume = volumeByGroup[group] ?? 0.0;
        return _MuscleFocusStat(
          group: group,
          volume: volume,
          sets: setsByGroup[group] ?? 0,
          exerciseCount: exercisesByGroup[group]?.length ?? 0,
          percentOfTotal: totalVolume > 0 ? volume / totalVolume : 0.0,
          normalized: maxVolume > 0 ? volume / maxVolume : 0.0,
        );
      }).toList();

      // Default selection: the most-trained group, so the detail card
      // isn't empty on first load. Null (no selection) only if nothing
      // was trained at all — the empty state handles that case instead.
      String? defaultSelection;
      if (totalVolume > 0) {
        defaultSelection =
            (stats.reduce((a, b) => a.volume >= b.volume ? a : b)).group;
      }

      if (!mounted) return;
      setState(() {
        _muscleFocusStats = stats;
        _selectedMuscleFocusGroup = defaultSelection;
        _muscleFocusLoading = false;
      });
    } catch (e) {
      debugPrint('CoachScreen muscle focus error: $e');
      if (!mounted) return;
      setState(() => _muscleFocusLoading = false);
    }
  }

  /// Rule-based, descriptive-only sentence — no health/medical claims,
  /// per spec. Prefers flagging an under-trained group (more actionable)
  /// over just naming the top two, if one clearly stands out.
  String _muscleFocusInsight() {
    final trained = _muscleFocusStats.where((s) => s.volume > 0).toList();
    if (trained.isEmpty) return '';

    final sorted = [..._muscleFocusStats]
      ..sort((a, b) => a.volume.compareTo(b.volume));
    final avg = trained.fold(0.0, (a, b) => a + b.volume) / trained.length;
    final lowest = sorted.first;

    if (lowest.volume == 0 || (avg > 0 && lowest.volume < avg * 0.3)) {
      return 'Your ${lowest.group.toLowerCase()} received significantly '
          'less training than other muscle groups this period.';
    }

    final topTwo =
        sorted.reversed.take(2).map((s) => s.group).join(' and ');
    return 'Your $topTwo received the most training this period.';
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

      final records = await WeightRecordService().getAllRecordsAscending(_uid!);

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

  // MONTHLY OVERVIEW (streak + workout total + calendar)

  /// Pure re-derivation from _trendLogs. Called after every fetch and on
  /// every month-navigation tap — never touches Firestore itself.
  void _recomputeMonthlyOverview() {
    final Set<DateTime> dates = {};
    for (final log in _trendLogs) {
      final completedAt =
          DateTime.tryParse(log['completedAt'] as String? ?? '');
      if (completedAt == null) continue;
      dates.add(DateTime(completedAt.year, completedAt.month, completedAt.day));
    }

    _workoutDates = dates;
    _currentStreak = _computeStreak(dates);
    _workoutsInDisplayedMonth = dates
        .where((d) =>
            d.year == _displayedMonth.year && d.month == _displayedMonth.month)
        .length;
  }

  /// Consecutive-day streak ending at "today" (or "yesterday" if today's
  /// workout just hasn't happened yet) — deliberately NOT derived from
  /// _workoutsInDisplayedMonth, per the spec's explicit distinction.
  int _computeStreak(Set<DateTime> dates) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    DateTime cursor;
    if (dates.contains(today)) {
      cursor = today;
    } else if (dates.contains(today.subtract(const Duration(days: 1)))) {
      cursor = today.subtract(const Duration(days: 1));
    } else {
      return 0;
    }

    int streak = 0;
    while (dates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  void _changeDisplayedMonth(int delta) {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + delta, 1);
      // Only _workoutsInDisplayedMonth actually changes here — streak is
      // "today"-anchored and intentionally untouched by month navigation.
      _workoutsInDisplayedMonth = _workoutDates
          .where((d) =>
              d.year == _displayedMonth.year &&
              d.month == _displayedMonth.month)
          .length;
    });
  }

  /// Pure function: given raw logs + a range index, returns the bucketed
  /// points for that range. No Firestore access — safe to call on every
  /// filter tap.
  List<_TrendPoint> _buildTrendPoints(
      List<Map<String, dynamic>> logs, int rangeIndex) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    late List<_TrendPoint> buckets;
    late int Function(DateTime logDate) bucketIndexOf;

    if (rangeIndex == 0) {
      // WEEK — 7 daily buckets, Monday-start (matches the old weekly card).
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      const dayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      buckets = List.generate(
        7,
        (i) => _TrendPoint(
          bucketStart: weekStart.add(Duration(days: i)),
          label: dayLabels[i],
        ),
      );
      bucketIndexOf = (logDate) => logDate.difference(weekStart).inDays;
    } else if (rangeIndex == 1) {
      // MONTH — 30 daily buckets, today back to 29 days ago.
      final monthStart = today.subtract(const Duration(days: 29));
      buckets = List.generate(30, (i) {
        final day = monthStart.add(Duration(days: i));
        return _TrendPoint(bucketStart: day, label: '${day.day}');
      });
      bucketIndexOf = (logDate) => logDate.difference(monthStart).inDays;
    } else {
      // 3 MONTHS — 13 weekly buckets, Monday-start weeks.
      final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
      final rangeStart = thisWeekStart.subtract(const Duration(days: 7 * 12));
      buckets = List.generate(13, (i) {
        final weekStart = rangeStart.add(Duration(days: 7 * i));
        return _TrendPoint(
          bucketStart: weekStart,
          label: '${_kMonthAbbrev[weekStart.month - 1]} ${weekStart.day}',
        );
      });
      bucketIndexOf =
          (logDate) => logDate.difference(rangeStart).inDays ~/ 7;
    }

    for (final log in logs) {
      final completedStr = log['completedAt'] as String? ?? '';
      final completedAt = DateTime.tryParse(completedStr);
      if (completedAt == null) continue;
      final logDate =
          DateTime(completedAt.year, completedAt.month, completedAt.day);

      final index = bucketIndexOf(logDate);
      if (index < 0 || index >= buckets.length) continue;

      final bucket = buckets[index];
      bucket.workoutCount += 1;
      bucket.totalVolume += (log['totalVolume'] as num?)?.toDouble() ?? 0.0;
      bucket.totalDurationMins +=
          (log['totalDurationMins'] as num?)?.toDouble() ?? 0.0;
    }

    return buckets;
  }

  Future<void> _loadStats() async {
    if (_uid == null) return;
    setState(() => _statsLoading = true);

    try {
      // Get all recent logs
      final logs = await WorkoutLogService().getRecentLogs(_uid!, limit: 50);

      // Get active plan to count planned workouts this week
      final plan = await WorkoutPlanService().getActivePlan(_uid!);

      // Compute weekly volume 
      final now = DateTime.now();
      // Find start of current week (Monday)
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

      int workoutsThisWeek = 0;

      for (final log in logs) {
        final completedStr = log['completedAt'] as String? ?? '';
        if (completedStr.isEmpty) continue;
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;

        final logDate = DateTime(completedAt.year, completedAt.month, completedAt.day);

        // Only count logs from this week
        if (logDate.isAfter(weekStartDate.subtract(const Duration(days: 1)))) {
          workoutsThisWeek++;
        }
      }

      // Count planned workout days this week (non-rest days)
      int plannedThisWeek = 0;
      if (plan != null) {
        final days = plan['days'] as List<dynamic>? ?? [];
        for (final day in days) {
          final dayType = day['dayType'] as String? ?? '';
          if (dayType == 'workout') plannedThisWeek++;
        }
      }

      // Compute muscle frequency from exerciseLogs subcollections
      final Map<String, int> muscleFreq = {};
      final logDocs = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .get();

      for (final logDoc in logDocs.docs) {
        final completedStr = logDoc.data()['completedAt'] as String? ?? '';
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;
        final logDate = DateTime(completedAt.year, completedAt.month, completedAt.day);
        if (!logDate.isAfter(weekStartDate.subtract(const Duration(days: 1)))) continue;

        final exLogs = await logDoc.reference.collection('exerciseLogs').get();
        for (final ex in exLogs.docs) {
          final muscle = ex.data()['muscleGroup'] as String? ?? 'other';
          muscleFreq[muscle] = (muscleFreq[muscle] ?? 0) + 1;
        }
      }

      setState(() {
        _recentLogs = logs;
        _workoutsThisWeek = workoutsThisWeek;
        _plannedThisWeek = plannedThisWeek;
        _muscleFrequency = muscleFreq;
        _statsLoading = false;
      });
    } catch (e, stack) {
      debugPrint('CoachScreen recovery error: $e');
      debugPrint('$stack');
      setState(() => _recoveryLoading = false);
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
      print('CoachScreen recovery error: $e');
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
            Expanded(
              child: _selectedTab == 0
                  ? _buildStatsTab()
                  : _selectedTab == 1
                      ? _buildRecoveryTab()
                      : _buildRecordsTab(),
            ),
          ],
        ),
      ),
    );
  }

  // Header
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
          const SizedBox(height: 4),
          Text(
            'AI PERFORMANCE\nINSIGHTS',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  // Segmented switch
  Widget _buildSegmentedSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildSegmentBtn('STATS REPORT', 0),
            _buildSegmentBtn('RECOVERY MAP', 1),
            _buildSegmentBtn('RECORDS', 2),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // STATS TAB
  Widget _buildStatsTab() {
    if (_statsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        _buildTrendsCard(),
        const SizedBox(height: 16),
        _buildMuscleFocusCard(),
        const SizedBox(height: 16),
        _buildMonthlyOverviewCard(),
        const SizedBox(height: 16),
        _buildAdherenceCard(),
        const SizedBox(height: 16),
        _buildConsistencyCard(),
        const SizedBox(height: 16),
        _buildMuscleBreakdownCard(),
        const SizedBox(height: 16),
        _buildProgressionCard(),
        const SizedBox(height: 24),
        _buildResetPlanButton(),
      ],
    );
  }

  // Training Trends (redesigned Weekly Volume section)
  Widget _buildTrendsCard() {
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
            'Training Trends',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            'Workouts · Volume · Duration',
            style: GoogleFonts.manrope(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildTrendsRangeChips(),
          const SizedBox(height: 20),
          if (_trendsLoading)
            const SizedBox(
              height: 210,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            SizedBox(
              height: 210,
              child: PageView(
                controller: _trendsPageController,
                onPageChanged: (i) => setState(() => _trendsCarouselPage = i),
                children: [
                  _buildBarTrendPanel(
                    title: 'WORKOUTS',
                    unitLabel: 'SESSIONS',
                    valueOf: (p) => p.workoutCount.toDouble(),
                    formatTotal: (v) => v.toStringAsFixed(0),
                  ),
                  _buildBarTrendPanel(
                    title: 'VOLUME',
                    unitLabel: 'KG',
                    valueOf: (p) => p.totalVolume,
                    formatTotal: (v) => v.toStringAsFixed(0),
                  ),
                  _buildDurationTrendPanel(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildTrendsDots(),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendsRangeChips() {
    return Row(
      children: List.generate(_trendsRangeLabels.length, (i) {
        final isSelected = _trendsRangeIndex == i;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _onTrendsRangeChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _trendsRangeLabels[i],
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isSelected
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTrendsDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isActive = _trendsCarouselPage == i;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : AppColors.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  /// Pixel width reserved per data point before horizontal scrolling
  /// kicks in. Week always fits on screen (7 points); Month and 3-Months
  /// use a fixed width so they scroll once the point count exceeds it.
  double _pxPerTrendPoint(double availableWidth) {
    switch (_trendsRangeIndex) {
      case 0:
        return availableWidth / 7; // fills exactly, no scroll needed
      case 1:
        return 34.0; // 30 points → scrolls
      default:
        return 56.0; // 13 points, wider labels ("JUL 7") → scrolls sooner
    }
  }

  /// Shared frame for the Workouts and Volume panels (both bar charts).
  /// [valueOf] pulls the metric out of a _TrendPoint; kept generic so the
  /// bucketing logic in _buildTrendPoints only has to run once.
  Widget _buildBarTrendPanel({
    required String title,
    required String unitLabel,
    required double Function(_TrendPoint) valueOf,
    required String Function(double) formatTotal,
  }) {
    final values = _trendPoints.map(valueOf).toList();
    final total = values.fold(0.0, (a, b) => a + b);
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final hasData = total > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '${formatTotal(total)} $unitLabel',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: !hasData
              ? _buildTrendEmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final pxPerPoint = _pxPerTrendPoint(constraints.maxWidth);
                    final contentWidth = math.max(
                      constraints.maxWidth,
                      _trendPoints.length * pxPerPoint,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: BarChart(
                          BarChartData(
                            maxY: maxValue * 1.2,
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
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= _trendPoints.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _trendPoints[i].label,
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
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) =>
                                    AppColors.surfaceContainerHigh,
                                getTooltipItem: (group, gi, rod, ri) =>
                                    BarTooltipItem(
                                  rod.toY.toStringAsFixed(0),
                                  GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            barGroups: List.generate(_trendPoints.length, (i) {
                              final isLast = i == _trendPoints.length - 1;
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: values[i],
                                    width: pxPerPoint * 0.5,
                                    borderRadius: BorderRadius.circular(4),
                                    color: values[i] > 0
                                        ? (isLast
                                            ? AppColors.primary
                                            : AppColors.primary
                                                .withValues(alpha: 0.4))
                                        : AppColors.surfaceContainerHigh,
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDurationTrendPanel() {
    final values =
        _trendPoints.map((p) => p.totalDurationMins).toList();
    final total = values.fold(0.0, (a, b) => a + b);
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final hasData = total > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'DURATION',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '${total.toStringAsFixed(0)} MIN',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: !hasData
              ? _buildTrendEmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final pxPerPoint = _pxPerTrendPoint(constraints.maxWidth);
                    final contentWidth = math.max(
                      constraints.maxWidth,
                      _trendPoints.length * pxPerPoint,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxValue * 1.2,
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
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= _trendPoints.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _trendPoints[i].label,
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
                                          '${s.y.toStringAsFixed(0)} min',
                                          GoogleFonts.manrope(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.onSurface,
                                          ),
                                        ))
                                    .toList(),
                              ),
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
                                  color:
                                      AppColors.primary.withValues(alpha: 0.08),
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
    );
  }

  Widget _buildTrendEmptyState() {
    return Center(
      child: Text(
        'No data yet for this period',
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  // Monthly Overview
  Widget _buildMonthlyOverviewCard() {
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
            'MONTHLY OVERVIEW',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildCompactStatChip(
                  icon: Icons.local_fire_department_rounded,
                  value: '$_currentStreak',
                  label: 'Day Streak',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactStatChip(
                  icon: Icons.fitness_center_rounded,
                  value: '$_workoutsInDisplayedMonth',
                  label: 'Workouts',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildMonthCalendar(),
        ],
      ),
    );
  }

  Widget _buildCompactStatChip({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCalendar() {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstOfMonth = DateTime(year, month, 1);
    // DateTime.weekday: Monday = 1 .. Sunday = 7. Grid is Monday-start, so
    // this is how many blank leading cells the grid needs.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Column(
      children: [
        // Month navigation header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => _changeDisplayedMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded,
                  color: AppColors.onSurfaceVariant),
              splashRadius: 20,
            ),
            Text(
              '${_kMonthFullNames[month - 1]} $year',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            IconButton(
              onPressed: () => _changeDisplayedMonth(1),
              icon: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
              splashRadius: 20,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Weekday header (Monday-start, per spec)
        Row(
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (int i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (int day = 1; day <= daysInMonth; day++)
              _buildCalendarDayCell(
                date: DateTime(year, month, day),
                day: day,
                isToday: DateTime(year, month, day) == todayDate,
                hasWorkout:
                    _workoutDates.contains(DateTime(year, month, day)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarDayCell({
    required DateTime date,
    required int day,
    required bool isToday,
    required bool hasWorkout,
  }) {
    Color? fillColor;
    Color textColor = AppColors.onSurface;
    Border? border;

    if (hasWorkout) {
      fillColor = AppColors.primary;
      textColor = AppColors.onPrimary;
    }
    if (isToday) {
      border = Border.all(
        color: AppColors.primary,
        width: 1.5,
      );
      if (!hasWorkout) {
        textColor = AppColors.primary;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            border: border,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight:
                  isToday || hasWorkout ? FontWeight.w700 : FontWeight.w400,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  // Consistency

  Widget _buildMuscleFocusCard() {
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
                      'Muscle Focus',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'Identify areas that need more focus',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Shares the Week/Month/3-Months filter from Training
              // Trends above — this badge just makes that visible here
              // too, without duplicating the chip row.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _trendsRangeLabels[_trendsRangeIndex],
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_muscleFocusLoading)
            const SizedBox(
              height: 260,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_muscleFocusStats.every((s) => s.volume == 0))
            _buildMuscleFocusEmptyState()
          else ...[
            SizedBox(
              height: 260,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  radarBackgroundColor: Colors.transparent,
                  radarBorderData: BorderSide(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.15),
                  ),
                  gridBorderData: BorderSide(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.1),
                  ),
                  tickBorderData: const BorderSide(color: Colors.transparent),
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(
                    color: Colors.transparent,
                    fontSize: 0,
                  ),
                  titlePositionPercentageOffset: 0.18,
                  titleTextStyle: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                  getTitle: (index, angle) => RadarChartTitle(
                    text: _muscleFocusStats[index].group,
                  ),
                  dataSets: [
                    RadarDataSet(
                      dataEntries: _muscleFocusStats
                          .map((s) => RadarEntry(value: s.normalized * 100))
                          .toList(),
                      fillColor: AppColors.primary.withValues(alpha: 0.15),
                      borderColor: AppColors.primary,
                      borderWidth: 2,
                      entryRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildMuscleFocusIllustrationRow(),
            if (_selectedMuscleFocusGroup != null) ...[
              const SizedBox(height: 16),
              _buildMuscleFocusDetailCard(
                _muscleFocusStats.firstWhere(
                  (s) => s.group == _selectedMuscleFocusGroup,
                ),
              ),
            ],
            if (_muscleFocusInsight().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                _muscleFocusInsight(),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Tappable illustrations — this is how axis selection actually happens
  /// (see the note above _loadMuscleFocus: fl_chart's RadarTouchData only
  /// reports dataset index, not entry/axis index, so it can't tell us
  /// which muscle group was tapped on the chart itself).
  Widget _buildMuscleFocusIllustrationRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _muscleFocusStats.map((stat) {
        final isSelected = _selectedMuscleFocusGroup == stat.group;
        return GestureDetector(
          onTap: () => setState(() => _selectedMuscleFocusGroup = stat.group),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: Image.asset(
                    'assets/muscle_illustration/${stat.group.toLowerCase()}.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: Text(
                        stat.group[0],
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMuscleFocusDetailCard(_MuscleFocusStat stat) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.group,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${stat.volume.toStringAsFixed(0)} kg',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· ${(stat.percentOfTotal * 100).toStringAsFixed(0)}% of total volume',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${stat.sets} sets · ${stat.exerciseCount} '
            '${stat.exerciseCount == 1 ? 'exercise' : 'exercises'}',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuscleFocusEmptyState() {
    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radar_rounded,
              size: 32,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No workout data yet',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Log a workout to see your muscle focus.',
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

  Widget _buildConsistencyCard() {
    final rate = _plannedThisWeek > 0
        ? (_workoutsThisWeek / _plannedThisWeek).clamp(0.0, 1.0)
        : 0.0;
    final pct = (rate * 100).round();

    String message;
    if (pct >= 90) message = 'Elite level precision.';
    else if (pct >= 70) message = 'Solid consistency. Keep pushing.';
    else if (pct >= 50) message = 'Good start. Build the habit.';
    else if (_plannedThisWeek == 0) message = 'No plan active this week.';
    else message = 'Let\'s get moving. You\'ve got this.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            'Consistency',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          // Ring
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: rate,
                    strokeWidth: 10,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'GOAL HIT',
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You've completed $_workoutsThisWeek of your $_plannedThisWeek scheduled sessions. $message",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Muscle Breakdown
  Widget _buildMuscleBreakdownCard() {
    if (_muscleFrequency.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'Complete workouts to see muscle breakdown.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }

    final sorted = _muscleFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxFreq = sorted.first.value;

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
            'Muscle Focus This Week',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          ...sorted.take(5).map((entry) {
            final ratio = entry.value / maxFreq;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        '${entry.value}x',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // 4-Week Adherence Card
  Widget _buildAdherenceCard() {
    if (_adherenceLoading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final rate = _targetLast4Weeks > 0
        ? (_completedLast4Weeks / _targetLast4Weeks).clamp(0.0, 1.0)
        : 0.0;
    final pct = (rate * 100).round();

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
            '4-Week Adherence',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Consistency against your active plan',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: rate,
                        strokeWidth: 7,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  _targetLast4Weeks > 0
                      ? '$_completedLast4Weeks of $_targetLast4Weeks planned sessions completed over the last 28 days.'
                      : 'No active plan to compare against.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Exercise Progression Card
  Widget _buildProgressionCard() {
    if (_loggedExerciseNames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'Log a few workouts to see your strength progression.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }

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
            'Exercise Progression',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Exercise picker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedExercise,
                isExpanded: true,
                dropdownColor: AppColors.surfaceContainerHigh,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.onSurfaceVariant),
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
                items: _loggedExerciseNames
                    .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(name),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedExercise = value);
                  _loadExerciseProgression(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Range chips
          Row(
            children: List.generate(_progressionRangeLabels.length, (i) {
              final isSelected = _progressionRangeIndex == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _onRangeChanged(i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _progressionRangeLabels[i],
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isSelected
                            ? AppColors.onPrimary
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Chart
          SizedBox(
            height: 200,
            child: _progressionLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _progressionData.isEmpty
                    ? Center(
                        child: Text(
                          'No logs for this exercise in the selected range.',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      )
                    : _buildProgressionChart(),
          ),
          const SizedBox(height: 12),

          // Legend
          Row(
            children: [
              _buildLegendDot(AppColors.primary, 'Max Weight (kg)'),
              const SizedBox(width: 16),
              _buildLegendDot(const Color(0xFFE8A87C), 'RPE (1-10)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressionChart() {
    final maxWeight = _progressionData
        .map((p) => p['maxWeight'] as double)
        .reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxWeight <= 0 ? 10.0 : maxWeight * 1.2;

    final weightSpots = <FlSpot>[];
    final rpeSpots = <FlSpot>[]; // RPE scaled onto the weight axis for display

    for (int i = 0; i < _progressionData.length; i++) {
      final point = _progressionData[i];
      final weight = point['maxWeight'] as double;
      final rpe = point['rpe'] as double;
      weightSpots.add(FlSpot(i.toDouble(), weight));
      rpeSpots.add(FlSpot(i.toDouble(), (rpe / 10) * chartMaxY));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: chartMaxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.outlineVariant.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: chartMaxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: GoogleFonts.manrope(
                  fontSize: 9,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (_progressionData.length / 4).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _progressionData.length) {
                  return const SizedBox.shrink();
                }
                final date = _progressionData[idx]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.day}/${date.month}',
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
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainerHigh,
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final idx = spot.x.toInt();
                if (idx < 0 || idx >= _progressionData.length) return null;
                final point = _progressionData[idx];
                final isWeightLine = spot.barIndex == 0;
                return LineTooltipItem(
                  isWeightLine
                      ? '${point['maxWeight']} kg'
                      : 'RPE ${point['rpe']}',
                  GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isWeightLine ? AppColors.primary : const Color(0xFFE8A87C),
                  ),
                );
              }).whereType<LineTooltipItem>().toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: weightSpots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          LineChartBarData(
            spots: rpeSpots,
            isCurved: true,
            color: const Color(0xFFE8A87C),
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  // Reset Plan
  Widget _buildResetPlanButton() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Text(
              'Protocol Reset',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'This will erase your current AI-adapted plan. Only use this if your training goals have fundamentally shifted.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _showResetConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error.withOpacity(0.15),
              foregroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              'RESET WORKOUT PLAN',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showResetConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Workout Plan?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
            'Your current plan and all adaptations will be removed. A new plan will be generated.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset',
                style: GoogleFonts.manrope(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await _resetPlan();
  }

  Future<void> _resetPlan() async {
    if (_uid == null) return;
    try {
      // Mark all active plans as inactive
      final plansSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutPlans')
          .get();

      for (final doc in plansSnap.docs) {
        if (doc.data()['status'] == 'active') {
          await doc.reference.update({'status': 'inactive'});
        }
      }

      if (!mounted) return;
      // Navigate to plan generation screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlanGenerationScreen(
            data: OnboardingData(),
          ),
        ),
      );
    } catch (e) {
      print('Reset plan error: $e');
    }
  }

  // RECOVERY TAB
  Widget _buildRecoveryTab() {
    if (_recoveryLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        _buildHeatmapCard(),
        const SizedBox(height: 16),
        _buildRecoveryStatusCard(),
        const SizedBox(height: 16),
        _buildInjuryActionButtons(),
        const SizedBox(height: 16),
        _buildCoachInsightCard(),
      ],
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'BODY JOURNEY',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _buildBodyOverviewRow(),
        const SizedBox(height: 16),
        _buildWeightJourneyCard(),
        const SizedBox(height: 28),
        Text(
          'WORKOUT RECORDS',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _buildWorkoutRecordsCard(),
      ],
    );
  }

  Widget _buildBodyOverviewRow() {
    final weight = _currentWeightKg;
    final height = _profileHeightCm;
    final bmi = _currentBmi;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            // Weight is the only one of the 3 with somewhere to go when empty
            onTap: weight == null ? () => _openLogWeight() : null,
            child: _buildCompactStatChip(
              icon: Icons.monitor_weight_outlined,
              value: weight != null ? '${weight.toStringAsFixed(1)} ' : 'Tap to add',
              label: 'Weight',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCompactStatChip(
            icon: Icons.height_rounded,
            value: height != null ? '${height.toStringAsFixed(0)} ' : 'Not set',
            label: 'Height',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCompactStatChip(
            icon: Icons.calculate_outlined,
            value: bmi != null ? bmi.toStringAsFixed(1) : '--',
            label: 'BMI',
          ),
        ),
      ],
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
                child: Text(
                  'Weight Journey',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              GestureDetector(
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
                    child: SizedBox(
                      width: contentWidth,
                      child: LineChart(
                        LineChartData(
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
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  if (i < 0 || i >= _weightRecords.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = _weightRecords[i].date;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${_kMonthAbbrev[d.month - 1]} ${d.day}',
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
                      Expanded(
                        child: Text(
                          r.exerciseName,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${r.weightKg.toStringAsFixed(0)} kg × ${r.reps}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_kMonthAbbrev[r.achievedAt.month - 1]} ${r.achievedAt.day}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            Center(
              child: GestureDetector(
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
    debugPrint('muscleRecoveryData: ${_muscleRecoveryData.keys.toList()}, glutes doc: ${_muscleRecoveryData['Glutes']}');
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
    return GestureDetector(
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

  // Recovery Status List
  Widget _buildRecoveryStatusCard() {
    if (_injuries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'No injuries logged. Log an injury if you experience pain during training.',
          style: GoogleFonts.manrope(
              fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
      );
    }

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
            'Recovery Status',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ..._injuries.map((injury) => _buildInjuryRow(injury)),
        ],
      ),
    );
  }

  Widget _buildInjuryRow(Map<String, dynamic> injury) {
    final label = injury['label'] as String? ?? 'Unknown';
    final status = injury['status'] as String? ?? 'active';

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface)),
              Text(
                statusText,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
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

  // Action Buttons
  Widget _buildInjuryActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionBtn(
            icon: Icons.add_circle_outline_rounded,
            label: 'LOG NEW\nINJURY',
            onTap: _showLogInjurySheet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionBtn(
            icon: Icons.check_circle_outline_rounded,
            label: 'MARK\nRECOVERED',
            onTap: _showMarkRecoveredSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.onSurface,
              ),
            ),
          ],
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
  Future<void> _showLogInjurySheet() async {
    // All body regions from BodyRegion enum mapped to display names
    final regions = {
      'leftShoulder': 'Left Shoulder',
      'rightShoulder': 'Right Shoulder',
      'chest': 'Chest',
      'upperBack': 'Upper Back',
      'lowerBack': 'Lower Back',
      'leftArm': 'Left Arm',
      'rightArm': 'Right Arm',
      'core': 'Core / Abs',
      'leftHip': 'Left Hip',
      'rightHip': 'Right Hip',
      'leftKnee': 'Left Knee',
      'rightKnee': 'Right Knee',
      'leftAnkle': 'Left Ankle',
      'rightAnkle': 'Right Ankle',
      'neck': 'Neck',
    };

    String? selectedRegion;
    final labelController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LOG NEW INJURY',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface)),
              const SizedBox(height: 20),
              Text('Body Region',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 10),
              // Region chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: regions.entries.map((entry) {
                  final isSelected = selectedRegion == entry.key;
                  return GestureDetector(
                    onTap: () =>
                        setSheetState(() => selectedRegion = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(entry.value,
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('Description (optional)',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                style: GoogleFonts.manrope(
                    fontSize: 14, color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: "e.g. Runner's knee, shoulder strain",
                  hintStyle: GoogleFonts.manrope(
                      color: AppColors.onSurfaceVariant),
                  border: InputBorder.none,
                  fillColor: AppColors.surfaceContainerHigh,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: selectedRegion == null
                    ? null
                    : () async {
                        final label = labelController.text.trim().isEmpty
                            ? regions[selectedRegion!]!
                            : labelController.text.trim();
                        await _saveInjury(selectedRegion!, label);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                child: Text('SAVE INJURY',
                    style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInjury(String region, String label) async {
    if (_uid == null) return;
    await _db.collection('users').doc(_uid).collection('injuries').add({
      'region': region,
      'label': label,
      'isCustom': true,
      'status': 'active',
      'loggedAt': FieldValue.serverTimestamp(),
      'recoveredAt': null,
    });
    await _loadRecovery(); // refresh
  }

  Future<void> _showMarkRecoveredSheet() async {
    final activeInjuries = _injuries
        .where((i) => i['status'] != 'recovered')
        .toList();

    if (activeInjuries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No active injuries to update.',
              style: GoogleFonts.manrope()),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UPDATE RECOVERY',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface)),
            const SizedBox(height: 20),
            ...activeInjuries.map((injury) {
              final label = injury['label'] as String? ?? 'Unknown';
              final status = injury['status'] as String? ?? 'active';
              final id = injury['id'] as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface)),
                      ),
                      // Toggle between active → recovering → recovered
                      GestureDetector(
                        onTap: () async {
                          final nextStatus = status == 'active'
                              ? 'recovering'
                              : 'recovered';
                          await _updateInjuryStatus(id, nextStatus);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status == 'active' ? 'RECOVERING' : 'RECOVERED',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
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

  Color get _noDataColor => AppColors.onSurfaceVariant.withOpacity(0.25);
}