import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pressable.dart';
import '../data/exercise_data.dart';

/// Static exercise thumbnail (the demo GIF's first frame) for compact rows.
///
/// The illustrations are drawn on white, so the tile is white too — the
/// picture reads as a clean card rather than a white square sitting on a
/// grey one. [done] fades a check over it.
class ExerciseThumb extends StatelessWidget {
  final String? asset;
  final double size;
  final bool done;

  const ExerciseThumb({
    super.key,
    required this.asset,
    this.size = 56,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              ColoredBox(
                color: Colors.white,
                child: Image.asset(
                  asset!,
                  fit: BoxFit.cover,
                  // Some source thumbnails are 700px+; decode at tile size.
                  cacheWidth: (size * dpr).round(),
                  errorBuilder: (_, _, _) => _ThumbPlaceholder(size: size),
                ),
              )
            else
              _ThumbPlaceholder(size: size),
            AnimatedOpacity(
              opacity: done ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: Icon(Icons.check_rounded,
                    color: Colors.white, size: size * 0.42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of exercise thumbnails — as many as fit the width, then "+N".
/// Tapping a thumbnail plays that exercise's demo full-screen.
class ExerciseThumbStrip extends StatelessWidget {
  final List<String> exerciseNames;
  final double size;
  final double gap;

  /// Background of the "+N" tile — translucent over photos by default.
  final Color overflowColor;

  const ExerciseThumbStrip({
    super.key,
    required this.exerciseNames,
    this.size = 46,
    this.gap = 8,
    this.overflowColor = const Color(0x66000000),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            math.max(1, ((constraints.maxWidth + gap) / (size + gap)).floor());
        final overflow = exerciseNames.length > fits;
        final shown =
            exerciseNames.take(overflow ? fits - 1 : fits).toList();

        return Row(
          children: [
            for (final name in shown) ...[
              _thumb(context, name),
              SizedBox(width: gap),
            ],
            if (overflow)
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: overflowColor,
                  borderRadius: BorderRadius.circular(size * 0.24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(
                  '+${exerciseNames.length - shown.length}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _thumb(BuildContext context, String name) {
    final data = findExerciseByName(name);
    final gif = data?.localGifAsset;

    return Semantics(
      label: name,
      child: Pressable(
        onTap: gif == null
            ? null
            : () => showExerciseDemoFullscreen(context, gifAsset: gif, title: data!.name),
        child: ExerciseThumb(asset: data?.thumbnailAsset, size: size),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  final double size;

  const _ThumbPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceContainerHigh,
      child: Icon(Icons.fitness_center_rounded,
          size: size * 0.4, color: AppColors.onSurfaceVariant),
    );
  }
}

/// Looping demo for the exercise being worked on: the GIF on a white stage
/// (matching the illustrations' own background), a position [badge] in the
/// corner, and tap-to-enlarge.
class ExerciseDemoPanel extends StatelessWidget {
  final String gifAsset;
  final String title;
  final String badge;
  final Object heroTag;
  final double height;

  const ExerciseDemoPanel({
    super.key,
    required this.gifAsset,
    required this.title,
    required this.badge,
    required this.heroTag,
    this.height = 210,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Pressable(
      pressedScale: 0.985,
      onTap: () => showExerciseDemoFullscreen(
        context,
        gifAsset: gifAsset,
        title: title,
        heroTag: heroTag,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: height,
          color: Colors.white,
          child: Stack(
            children: [
              Positioned.fill(
                child: Hero(
                  tag: heroTag,
                  // Fly the already-decoded frame both ways, so the
                  // full-screen image loading doesn't flash mid-flight.
                  flightShuttleBuilder: (_, _, direction, fromContext, toContext) {
                    final hero = (direction == HeroFlightDirection.push
                        ? fromContext.widget
                        : toContext.widget) as Hero;
                    return hero.child;
                  },
                  child: Image.asset(
                    gifAsset,
                    fit: BoxFit.contain,
                    // A few GIFs are 1080px; there's no need to decode
                    // (and animate) more pixels than the panel shows.
                    cacheHeight: (height * dpr).round(),
                    // Rebuilds otherwise briefly blank the GIF.
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _OverlayPill(
                  child: Text(
                    badge,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 10,
                right: 10,
                child: _OverlayPill(
                  child: Icon(Icons.open_in_full_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  final Widget child;

  const _OverlayPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// Full-screen demo viewer over a dark scrim. Tap anywhere to close.
Future<void> showExerciseDemoFullscreen(
  BuildContext context, {
  required String gifAsset,
  required String title,
  Object? heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => _DemoViewer(
        gifAsset: gifAsset,
        title: title,
        heroTag: heroTag,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _DemoViewer extends StatelessWidget {
  final String gifAsset;
  final String title;
  final Object? heroTag;

  const _DemoViewer({
    required this.gifAsset,
    required this.title,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(gifAsset,
        fit: BoxFit.contain, gaplessPlayback: true);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          color: Colors.white,
                          child: heroTag == null
                              ? image
                              : Hero(tag: heroTag!, child: image),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  'TAP ANYWHERE TO CLOSE',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: Colors.white38,
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
