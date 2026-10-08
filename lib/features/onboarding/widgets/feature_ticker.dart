import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// A slow, endless marquee of what the app does, faded out at both edges.
///
/// Ambient rather than something to read closely: it gives first-time
/// visitors a sense of what's inside without adding another block of copy.
/// Holds still when the platform asks for reduced motion.
class FeatureTicker extends StatefulWidget {
  final List<String> items;

  /// Time for one full run of [items] to scroll past.
  final Duration period;

  const FeatureTicker({
    super.key,
    required this.items,
    this.period = const Duration(seconds: 40),
  });

  @override
  State<FeatureTicker> createState() => _FeatureTickerState();
}

class _FeatureTickerState extends State<FeatureTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.stop();
    } else if (!_scroll.isAnimating) {
      _scroll.repeat();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.manrope(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.4,
      color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
    );

    final run = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in widget.items) ...[
          Text(item.toUpperCase(), style: style),
          Container(
            width: 3,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      label: widget.items.join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          height: 16,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0x00FFFFFF),
                Color(0xFFFFFFFF),
                Color(0xFFFFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: [0, 0.14, 0.86, 1],
            ).createShader(bounds),
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                // Two copies side by side: sliding left by exactly one copy's
                // width lands on an identical frame, so the loop is seamless.
                child: AnimatedBuilder(
                  animation: _scroll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [run, run],
                  ),
                  builder: (context, child) => FractionalTranslation(
                    translation: Offset(-_scroll.value / 2, 0),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
