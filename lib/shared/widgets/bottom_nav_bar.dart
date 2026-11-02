import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import 'pressable.dart';

class RakanBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const RakanBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // minimum, not padding: the gap under the bar shouldn't stack on top of
    // the gesture-nav inset on phones that have one.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // The bar's height is fixed, so labels stop growing with the system
          // text size at the same point Material's NavigationBar stops them.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dashboard icon
                Expanded(
                  child: _NavItem(
                    icon: Icons.grid_view_outlined,
                    activeIcon: Icons.grid_view_rounded,
                    label: 'Dashboard',
                    isSelected: currentIndex == 0,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(0);
                    },
                  ),
                ),

                // Plan Schedule Icon
                Expanded(
                  child: _NavItem(
                    icon: Icons.calendar_month_outlined,
                    activeIcon: Icons.calendar_month_rounded,
                    label: 'Schedule',
                    isSelected: currentIndex == 1,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(1);
                    },
                  ),
                ),

                // Coach Icon
                Expanded(
                  child: _NavItem(
                    icon: Icons.auto_awesome_outlined,
                    activeIcon: Icons.auto_awesome_rounded,
                    label: 'Coach',
                    isSelected: currentIndex == 2,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(2);
                    },
                  ),
                ),

                // Settings Icon
                Expanded(
                  child: _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    isSelected: currentIndex == 3,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(3);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Private widget for this file
class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  static const double _iconSize = 24;

  // Overshoots, dips slightly, then settles.
  static final TweenSequence<double> _pop = TweenSequence([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.24,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.24,
        end: 0.96,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.96,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
  ]);

  // Starts at its end state so the tab that's already selected doesn't play
  // the animation when the shell first opens.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.isSelected ? 1 : 0,
  );

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      widget.isSelected ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Semantics: tells screen readers (TalkBack/VoiceOver) this is a tab
    // button and which tab is selected — GestureDetector alone exposes
    // neither.
    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: '${widget.label} tab',
      excludeSemantics: true,
      child: Pressable(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        pressedScale: 0.9,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final fill = const Interval(
              0,
              0.55,
              curve: Curves.easeOut,
            ).transform(t);
            final dot = const Interval(
              0.3,
              1,
              curve: Curves.easeOutBack,
            ).transform(t);
            // Only pop on the way in; backwards it would read as a wobble.
            final scale = _controller.status == AnimationStatus.reverse
                ? 1.0
                : _pop.transform(t);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(scale: scale, child: _buildIcon(fill)),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: Color.lerp(
                      AppColors.onSurfaceVariant,
                      AppColors.onSurface,
                      fill,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: dot.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scaleX: dot,
                    child: Container(
                      width: 18,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: AppColors.navAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIcon(double fill) {
    return SizedBox.square(
      dimension: _iconSize,
      child: Stack(
        children: [
          Opacity(
            opacity: 1 - fill,
            child: Icon(
              widget.icon,
              color: AppColors.onSurfaceVariant,
              size: _iconSize,
            ),
          ),
          if (fill > 0)
            ClipOval(
              clipper: _CenterRevealClipper(fill),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: AppColors.navAccent.createShader,
                child: Icon(
                  widget.activeIcon,
                  color: Colors.white,
                  size: _iconSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A circle growing out of the child's center. At 1 it reaches the corners,
/// so the whole child shows.
class _CenterRevealClipper extends CustomClipper<Rect> {
  final double progress;

  const _CenterRevealClipper(this.progress);

  @override
  Rect getClip(Size size) {
    final reach = size.longestSide * math.sqrt2 / 2;
    return Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: reach * progress,
    );
  }

  @override
  bool shouldReclip(_CenterRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
