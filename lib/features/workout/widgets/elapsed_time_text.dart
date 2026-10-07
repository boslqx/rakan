import 'dart:async';

import 'package:flutter/material.dart';

/// Live "mm:ss" (or "h:mm:ss") workout clock since [startedAt].
///
/// Its own small widget with its own timer, so only this text rebuilds
/// every second — not the whole workout screen.
class ElapsedTimeText extends StatefulWidget {
  final DateTime startedAt;
  final TextStyle? style;

  const ElapsedTimeText({super.key, required this.startedAt, this.style});

  @override
  State<ElapsedTimeText> createState() => _ElapsedTimeTextState();
}

class _ElapsedTimeTextState extends State<ElapsedTimeText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.startedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = h > 0 ? '$h:$m:$s' : '$m:$s';
    return Text(
      text,
      semanticsLabel: 'Workout time $text',
      style: (widget.style ?? const TextStyle())
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
