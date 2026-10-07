import 'package:flutter/material.dart';

/// Drop-in replacement for `GestureDetector(onTap:, child:)` that gives
/// visual feedback: the child shrinks slightly and dims while pressed.
///
/// The app's custom buttons and cards were plain GestureDetectors, which
/// show nothing when touched — taps felt unresponsive and users couldn't
/// tell whether a press had registered. Material's InkWell ripple doesn't
/// suit the design system's borderless tonal cards, so this uses a subtle
/// scale instead (the same pattern iOS and most fitness apps use).
///
/// When [onTap] is null the child is shown as-is with no feedback, matching
/// GestureDetector's behaviour for a disabled control.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior? behavior;

  /// How small the child gets while pressed (1.0 = no scaling).
  final double pressedScale;

  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.behavior,
    this.pressedScale = 0.97,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return GestureDetector(behavior: widget.behavior, child: widget.child);
    }

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: widget.behavior ?? HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.85 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
