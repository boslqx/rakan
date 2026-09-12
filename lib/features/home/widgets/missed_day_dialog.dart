import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../workout/services/adapt_service.dart';
import '../../workout/services/schedule_matcher.dart';

/// Shown on Home screen load whenever the user has missed scheduled day(s)
/// not yet acknowledged (Phase 25 — see AdaptService.findMissedDays).
///
/// [actionable] misses are still within the reschedule-eligible window and
/// get a live card: "Reschedule" (opens an inline day picker — only shown
/// when at least one valid day exists) and "Skip entirely". [autoSkipped]
/// misses already had their window expire and were auto-resolved as
/// skipped before this dialog was even built (see
/// AdaptService.findMissedDays) — they're read-only, collapsed into one
/// summary line.
///
/// Every per-item lookup/resolve call goes through the
/// `*Override` callbacks when provided, falling back to real
/// [AdaptService] calls otherwise — this is what lets a widget test drive
/// the dialog without touching Firestore.
class MissedDayDialog extends StatefulWidget {
  final String uid;
  final List<MissedDay> actionable;
  final List<MissedDay> autoSkipped;

  final Future<List<DateTime>> Function(MissedDay item)?
  findValidRescheduleDaysOverride;
  final Future<void> Function(MissedDay item, DateTime target)?
  resolveRescheduledOverride;
  final Future<void> Function(MissedDay item)? resolveSkippedOverride;

  const MissedDayDialog({
    super.key,
    required this.uid,
    required this.actionable,
    this.autoSkipped = const [],
    this.findValidRescheduleDaysOverride,
    this.resolveRescheduledOverride,
    this.resolveSkippedOverride,
  });

  @override
  State<MissedDayDialog> createState() => _MissedDayDialogState();
}

class _MissedDayDialogState extends State<MissedDayDialog> {
  // Lazy: constructing AdaptService touches FirebaseFirestore.instance, so
  // this must not run unless something actually falls through to the real
  // service — a fully-overridden instance (as in widget tests) should
  // never need Firebase at all.
  AdaptService? _adaptServiceInstance;
  AdaptService get _adaptService => _adaptServiceInstance ??= AdaptService();

  // All per-item transient state is keyed by MissedDay.key (muscleGroup +
  // date), never by list index or position — indices shift whenever an
  // earlier item is removed (an item resolving out of order), and keying
  // by index caused a real bug: the item that slid into a freed index
  // inherited stale "loaded"/"resolving" flags that belonged to whatever
  // used to be there, so it got stuck showing a permanent spinner that
  // nothing ever cleared. Keying by stable identity makes that whole bug
  // class impossible.
  late List<MissedDay> _items;
  final Map<String, List<DateTime>?> _candidates = {}; // null = still loading
  final Set<String> _resolving = {};
  final Set<String> _pickerOpenFor = {};
  bool _autoSkippedExpanded = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.actionable);
    for (final item in _items) {
      _loadCandidates(item);
    }
  }

  Future<List<DateTime>> _fetchCandidates(MissedDay item) {
    final override = widget.findValidRescheduleDaysOverride;
    if (override != null) return override(item);
    return _adaptService.findValidRescheduleDays(
      uid: widget.uid,
      muscleGroup: item.muscleGroup,
      missedDate: item.date,
    );
  }

  Future<void> _loadCandidates(MissedDay item) async {
    List<DateTime> candidates;
    try {
      candidates = await _fetchCandidates(item);
    } catch (e) {
      // Treat a failed lookup as "no valid day" rather than leaving the
      // spinner stuck — the user can still skip.
      candidates = const [];
    }
    if (!mounted) return;
    setState(() => _candidates[item.key] = candidates);
  }

  Future<void> _skipAction(MissedDay item) {
    final override = widget.resolveSkippedOverride;
    if (override != null) return override(item);
    return _adaptService.resolveMissedDayAsSkipped(
      uid: widget.uid,
      muscleGroup: item.muscleGroup,
      missedDate: item.date,
    );
  }

  Future<void> _rescheduleAction(MissedDay item, DateTime target) {
    final override = widget.resolveRescheduledOverride;
    if (override != null) return override(item, target);
    return _adaptService.resolveMissedDayAsRescheduled(
      uid: widget.uid,
      muscleGroup: item.muscleGroup,
      missedDate: item.date,
      rescheduledTo: target,
    );
  }

  Future<void> _resolve(MissedDay item, Future<void> Function() action) async {
    setState(() => _resolving.add(item.key));

    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving.remove(item.key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Something went wrong — try again.',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return; // keep the card so the user can retry, instead of pretending it resolved
    }

    if (!mounted) return;
    setState(() {
      _items.removeWhere((m) => m.key == item.key);
      _candidates.remove(item.key);
      _resolving.remove(item.key);
      _pickerOpenFor.remove(item.key);
    });

    // Nothing actionable left and nothing read-only to show either ->
    // close automatically rather than making the user tap an extra "GOT
    // IT" just to leave an empty dialog. When there IS an auto-skipped
    // summary to show, stay open — the explicit close button in build()
    // handles that case instead.
    if (_items.isEmpty && widget.autoSkipped.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  String _dateLabel(DateTime date) =>
      '${_weekdayLabel(date.weekday)} ${date.day}/${date.month}';

  @override
  Widget build(BuildContext context) {
    final totalCount = _items.length + widget.autoSkipped.length;

    return Dialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        // Bounded so the dialog never tries to render taller than the
        // screen — with the day picker expanded and several missed
        // muscle groups shown at once, unbounded content here is exactly
        // what produced the reported overflow. The inner scroll view
        // handles anything past this height.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      totalCount == 1
                          ? 'YOU MISSED A SESSION'
                          : 'YOU MISSED SOME SESSIONS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Choose what to do with each one — reschedule it, or skip it entirely.',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._dateGroups().map(_dateGroupCard),
                      if (widget.autoSkipped.isNotEmpty) _autoSkippedSummary(),
                    ],
                  ),
                ),
              ),
              if (_items.isEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'GOT IT',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Groups the current [_items] by calendar date, preserving each date's
  /// first-seen order — this is purely a rendering grouping, recomputed on
  /// every build from whatever is left in [_items]. It never touches the
  /// underlying data model: [MissedDay] instances stay keyed by
  /// muscleGroup + date exactly as before (Decision #47), this just
  /// decides how to lay them out under shared date headers. Because it's
  /// derived fresh each build, a date's group shrinks (and vanishes once
  /// empty) automatically as its rows resolve one by one.
  List<List<MissedDay>> _dateGroups() {
    final Map<String, List<MissedDay>> grouped = {};
    final List<String> order = [];
    for (final item in _items) {
      final dateKey = ScheduleMatcher.dateKey(item.date);
      final group = grouped.putIfAbsent(dateKey, () {
        order.add(dateKey);
        return [];
      });
      group.add(item);
    }
    return order.map((dateKey) => grouped[dateKey]!).toList();
  }

  Widget _dateGroupCard(List<MissedDay> group) {
    final date = group.first.date;
    return Container(
      key: ValueKey('date-group-${ScheduleMatcher.dateKey(date)}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dateLabel(date),
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          for (var i = 0; i < group.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.15),
              ),
            ],
            const SizedBox(height: 12),
            _muscleGroupRow(group[i]),
          ],
        ],
      ),
    );
  }

  Widget _muscleGroupRow(MissedDay item) {
    final isResolving = _resolving.contains(item.key);
    final candidates = _candidates[item.key];
    final pickerOpen = _pickerOpenFor.contains(item.key);

    return Column(
      key: ValueKey(item.key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.muscleGroup,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        if (isResolving || candidates == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          )
        else if (pickerOpen)
          _dayPicker(item, candidates)
        else
          Row(
            children: [
              if (candidates.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _pickerOpenFor.add(item.key)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'RESCHEDULE',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _resolve(item, () => _skipAction(item)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerHigh,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'SKIP ENTIRELY',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _dayPicker(MissedDay item, List<DateTime> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHOOSE A DAY',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidates
              .map(
                (date) => OutlinedButton(
                  onPressed: () =>
                      _resolve(item, () => _rescheduleAction(item, date)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _dateLabel(date).toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _pickerOpenFor.remove(item.key)),
          child: Text(
            'CANCEL',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _autoSkippedSummary() {
    final count = widget.autoSkipped.length;
    return Padding(
      padding: EdgeInsets.only(top: _items.isEmpty ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _autoSkippedExpanded = !_autoSkippedExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You also missed $count ${count == 1 ? 'workout' : 'workouts'} '
                      'over the past few weeks',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    _autoSkippedExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_autoSkippedExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.autoSkipped
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${item.muscleGroup} — ${_dateLabel(item.date)} — skipped',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
