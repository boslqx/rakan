import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

/// The Rakan ribbon mark, lit like polished metal.
///
/// It materialises out of the dark (blurred and dim → sharp and lit) as a
/// band of light sweeps across it, then rests on a softly breathing glow and
/// catches the light again every few seconds. While [busy] the sweep loops
/// back-to-back, so the mark itself doubles as the loading indicator.
///
/// Dragging across the mark tilts it in 3D and the highlight follows the
/// finger; letting go springs it back. It's a small toy that invites the
/// first touch.
class BrandMark extends StatefulWidget {
  /// Height of the mark itself. The glow spills outside these bounds.
  final double height;

  /// Loop the light sweep continuously (loading) instead of occasionally.
  final bool busy;

  /// Called once the entrance animation has finished (or immediately when
  /// the platform asks for reduced motion).
  final VoidCallback? onIntroComplete;

  const BrandMark({
    super.key,
    this.height = 150,
    this.busy = false,
    this.onIntroComplete,
  });

  static const asset = 'assets/images/logo_mark.png';

  /// Width / height of [asset].
  static const aspectRatio = 759 / 1089;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with TickerProviderStateMixin {
  // A sweep takes ~1.2s in both modes, so switching mode mid-sweep doesn't
  // change its speed. Busy: sweep, short rest. Idle: sweep, long rest.
  static const _busyPeriod = Duration(milliseconds: 1600);
  static const _busySweep = 0.75;
  static const _idlePeriod = Duration(milliseconds: 5400);
  static const _idleSweep = 0.22;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  late final AnimationController _sweep = AnimationController(vsync: this);
  late final AnimationController _settle = AnimationController.unbounded(
    vsync: this,
  );

  bool _started = false;
  bool _reduceMotion = false;

  // Tilt in [-1, 1] on each axis, from where the finger is on the mark.
  bool _dragging = false;
  Offset _dragTilt = Offset.zero;
  Offset _releasedTilt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _startLoops();
      widget.onIntroComplete?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;

    if (_reduceMotion) {
      // Shows the mark fully lit with no sweep or breathing.
      _intro.value = 1;
      return;
    }
    // Wait for the image to decode so the entrance isn't spent on an empty
    // box. precacheImage completes even if loading fails.
    precacheImage(const AssetImage(BrandMark.asset), context).then((_) {
      if (mounted) _intro.forward();
    });
  }

  @override
  void didUpdateWidget(BrandMark old) {
    super.didUpdateWidget(old);
    if (old.busy != widget.busy && _intro.isCompleted) {
      _restartSweep(fromBusy: old.busy);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    _sweep.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _startLoops() {
    if (_reduceMotion) return;
    _breath.repeat(reverse: true);
    // The entrance already ended on a sweep, so start in the rest phase.
    _sweep
      ..duration = widget.busy ? _busyPeriod : _idlePeriod
      ..value = _sweepFraction(widget.busy)
      ..repeat();
  }

  /// Switches the sweep cadence, carrying an in-flight sweep across so the
  /// band doesn't jump.
  void _restartSweep({required bool fromBusy}) {
    if (_reduceMotion) return;
    final oldFraction = _sweepFraction(fromBusy);
    final newFraction = _sweepFraction(widget.busy);
    final inSweep = _sweep.value < oldFraction;
    final progress = _sweep.value / oldFraction;
    _sweep
      ..duration = widget.busy ? _busyPeriod : _idlePeriod
      ..value = inSweep ? progress * newFraction : newFraction
      ..repeat();
  }

  static double _sweepFraction(bool busy) => busy ? _busySweep : _idleSweep;

  // ── Touch tilt ─────────────────────────────────────────────────────────

  Offset _tiltFor(Offset local, Size size) {
    final dx = (local.dx / size.width) * 2 - 1;
    final dy = (local.dy / size.height) * 2 - 1;
    return Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
  }

  void _onPanStart(DragStartDetails d, Size size) {
    HapticFeedback.selectionClick();
    _settle.stop();
    setState(() {
      _dragging = true;
      _dragTilt = _tiltFor(d.localPosition, size);
    });
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    setState(() => _dragTilt = _tiltFor(d.localPosition, size));
  }

  void _onPanEnd() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _releasedTilt = _dragTilt;
    });
    // Slightly under-damped so it wobbles once before settling.
    _settle.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 170, damping: 12),
        1,
        0,
        0,
      ),
    );
  }

  Offset get _tilt => _dragging ? _dragTilt : _releasedTilt * _settle.value;

  // ── Light band ─────────────────────────────────────────────────────────

  /// Where the light band sits (0 = off the left edge, 1 = off the right
  /// edge) and how bright it is. Strength 0 means no band.
  (double, double) _band(Offset tilt) {
    final touchStrength = (tilt.distance * 1.4).clamp(0.0, 1.0);
    if (_dragging || touchStrength > 0.02) {
      return (0.5 + tilt.dx * 0.3, touchStrength);
    }
    if (!_intro.isCompleted) {
      final t = const Interval(
        0.15,
        1,
        curve: Curves.easeInOutSine,
      ).transform(_intro.value);
      return (t, 1);
    }
    final fraction = _sweepFraction(widget.busy);
    if (!_sweep.isAnimating || _sweep.value >= fraction) return (0, 0);
    return (Curves.easeInOutSine.transform(_sweep.value / fraction), 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.height * BrandMark.aspectRatio, widget.height);

    final image = Image.asset(
      BrandMark.asset,
      width: size.width,
      height: size.height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );

    return Semantics(
      image: true,
      label: 'Rakan',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _onPanStart(d, size),
        onPanUpdate: (d) => _onPanUpdate(d, size),
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: _onPanEnd,
        child: SizedBox.fromSize(
          size: size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _breath, _sweep, _settle]),
            child: image,
            builder: (context, image) {
              final i = _intro.value;
              final appear = Curves.easeOut.transform(
                (i / 0.4).clamp(0.0, 1.0),
              );
              final settle = const Interval(
                0,
                0.85,
                curve: Curves.easeOutCubic,
              ).transform(i);
              final blur =
                  14 *
                  (1 -
                      Curves.easeOutCubic.transform(
                        (i / 0.65).clamp(0.0, 1.0),
                      ));
              final lit = ui.lerpDouble(
                0.22,
                1,
                const Interval(0.2, 0.95, curve: Curves.easeInOut).transform(i),
              )!;
              final glow = const Interval(
                0.3,
                1,
                curve: Curves.easeOut,
              ).transform(i);
              final breath = Curves.easeInOut.transform(_breath.value);

              final tilt = _tilt;
              final (bandPos, bandStrength) = _band(tilt);

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Shade: pools darkness behind the mark so it and its glow
                  // stand clear of a busy photo. Invisible on a plain dark
                  // background.
                  Positioned(
                    left: size.width / 2 - size.height * 1.7,
                    top: size.height / 2 - size.height * 1.7,
                    width: size.height * 3.4,
                    height: size.height * 3.4,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: glow,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.surface.withValues(alpha: 0.85),
                                AppColors.surface.withValues(alpha: 0.55),
                                AppColors.surface.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Glow: a lit-from-behind halo, breathing slowly.
                  Positioned(
                    left: size.width / 2 - size.height * 1.05,
                    top: -size.height * 0.55,
                    width: size.height * 2.1,
                    height: size.height * 2.1,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: glow * (0.7 + 0.3 * breath),
                        child: Transform.scale(
                          scale: 0.96 + 0.08 * breath,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x33C6C6C7),
                                  Color(0x14C6C6C7),
                                  Color(0x00C6C6C7),
                                ],
                                stops: [0, 0.42, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: appear,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..translateByDouble(0, 10 * (1 - settle), 0, 1)
                        ..rotateX(-tilt.dy * 0.35)
                        ..rotateY(tilt.dx * 0.45)
                        ..scaleByDouble(
                          ui.lerpDouble(0.88, 1, settle)!,
                          ui.lerpDouble(0.88, 1, settle)!,
                          1,
                          1,
                        ),
                      child: ImageFiltered(
                        enabled: blur > 0.05,
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                          tileMode: TileMode.decal,
                        ),
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (bounds) =>
                              _bandShader(bounds, bandPos, bandStrength),
                          child: ShaderMask(
                            blendMode: BlendMode.modulate,
                            shaderCallback: (bounds) =>
                                _metalShader(bounds, lit),
                            child: image,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Brushed-silver toning: full white top-left falling to the app's
  /// metallic grey bottom-right, scaled by [lit] for the entrance.
  static Shader _metalShader(Rect bounds, double lit) {
    Color shade(Color c) => Color.lerp(Colors.black, c, lit)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        shade(Colors.white),
        shade(const Color(0xFFE4E5E8)),
        shade(AppColors.primary),
      ],
      stops: const [0, 0.5, 1],
    ).createShader(bounds);
  }

  /// A diagonal specular highlight, slid across the mark by [position].
  static Shader _bandShader(Rect bounds, double position, double strength) {
    final white = Colors.white;
    return LinearGradient(
      begin: const Alignment(-1, -0.45),
      end: const Alignment(1, 0.45),
      colors: [
        white.withValues(alpha: 0),
        white.withValues(alpha: 0.25 * strength),
        white.withValues(alpha: 0.95 * strength),
        white.withValues(alpha: 0.25 * strength),
        white.withValues(alpha: 0),
      ],
      stops: const [0.3, 0.43, 0.5, 0.57, 0.7],
      transform: _SlideX((position * 2 - 1) * bounds.width * 1.2),
    ).createShader(bounds);
  }
}

class _SlideX extends GradientTransform {
  final double dx;
  const _SlideX(this.dx);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}
