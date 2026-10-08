import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Small dot that sends out a soft ripple every few seconds — signals the
/// session clock is live. Holds still when the system asks for reduced
/// motion.
class LivePulseDot extends StatefulWidget {
  final double size;
  final Color color;

  const LivePulseDot({
    super.key,
    this.size = 7,
    this.color = AppColors.primary,
  });

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: 1, // ripple finished = invisible
  );
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    // One ripple every few seconds rather than a looping animation, which
    // would keep the screen redrawing at 60fps for the whole workout.
    _controller.forward(from: 0);
    _timer = Timer.periodic(
        const Duration(seconds: 3), (_) => _controller.forward(from: 0));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );

    return SizedBox.square(
      dimension: widget.size * 2.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final t = Curves.easeOut.transform(_controller.value);
              return Opacity(
                opacity: (1 - t) * 0.55,
                child: Transform.scale(scale: 1 + t * 1.6, child: dot),
              );
            },
          ),
          dot,
        ],
      ),
    );
  }
}

/// Session progress split into one segment per exercise; each fills as its
/// sets are ticked off. [highlighted] marks the exercise currently open.
class SegmentedProgress extends StatelessWidget {
  final List<double> values;
  final int? highlighted;

  const SegmentedProgress({super.key, required this.values, this.highlighted});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 4,
                color: i == highlighted
                    ? AppColors.surfaceBright
                    : AppColors.surfaceContainerHigh,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: values[i].clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    heightFactor: 1,
                    child: const ColoredBox(color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A number that counts up (or down) to [value] whenever it changes.
class AnimatedCount extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final String? suffix;
  final TextStyle? suffixStyle;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.suffix,
    this.suffixStyle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text.rich(
        TextSpan(
          text: format(v),
          children: [
            if (suffix != null) TextSpan(text: suffix, style: suffixStyle),
          ],
        ),
        maxLines: 1,
        style: style.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// One short bar per set: filled when done, dim while still to do.
class SetDots extends StatelessWidget {
  final int total;
  final Set<int> completed;

  const SetDots({super.key, required this.total, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (int i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 14,
            height: 4,
            decoration: BoxDecoration(
              color: completed.contains(i)
                  ? AppColors.primary
                  : AppColors.surfaceBright,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
