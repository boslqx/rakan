import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pressable.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/register_screen.dart';
import '../../auth/services/auth_navigation_service.dart';
import '../widgets/brand_mark.dart';
import '../widgets/feature_ticker.dart';

enum _Stage { loading, welcome, failed }

/// First screen of the app.
///
/// The native launch screen is a plain dark field. Out of it the Rakan mark
/// materialises in the centre while the session is restored. Signed-in users
/// then fade straight into the app. Everyone else watches the mark glide up
/// as the photo, copy and actions rise in beneath it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _backgroundAsset = 'assets/images/welcome_bg.jpg';

  static const _features = [
    'Adaptive plans',
    'Guided workouts',
    'Recovery tracking',
    'Plateau detection',
    'Progress stats',
    'Workout reminders',
    'Follow friends',
  ];

  _Stage _stage = _Stage.loading;
  bool _retrying = false;

  /// Completes when the mark has finished materialising, so routing never
  /// cuts the entrance short.
  final _introDone = Completer<void>();

  /// Hand-off from the centred loading mark to the welcome / error layout.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Slow Ken Burns drift on the background photo.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    _checkAuthAndRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the photo while the mark is on screen so the reveal never
    // waits on it.
    precacheImage(_backgroundImage(context), context);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _drift.dispose();
    super.dispose();
  }

  /// The welcome photo decoded at screen resolution rather than its full
  /// 2369×4212, which would cost ~40 MB of memory for no visible gain.
  ImageProvider _backgroundImage(BuildContext context) {
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context) *
                1.15)
            .round();
    return ResizeImage(const AssetImage(_backgroundAsset), width: width);
  }

  void _onIntroComplete() {
    if (!_introDone.isCompleted) _introDone.complete();
  }

  Future<void> _checkAuthAndRoute() async {
    // Wait for Firebase to restore persisted session.
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (user == null) {
      await _introDone.future;
      if (!mounted) return;
      _show(_Stage.welcome);
      return;
    }

    // Logged in → let the centralized navigation service decide.
    // This reads Firestore; if it fails (no connection, a timeout) show a
    // retry instead of leaving the user on an endless loading screen.
    try {
      final next = await AuthNavigationService().resolveNextScreen().timeout(
        const Duration(seconds: 20),
      );
      await _introDone.future;
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => next,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      debugPrint('Startup routing failed: $e');
      await _introDone.future;
      if (!mounted) return;
      _show(_Stage.failed);
    }
  }

  void _show(_Stage stage) {
    setState(() {
      _stage = stage;
      _retrying = false;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
      return;
    }
    _reveal.forward();
    if (stage == _Stage.welcome) _drift.repeat(reverse: true);
  }

  void _retry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    _checkAuthAndRoute();
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_stage) {
      _Stage.loading => null,
      _Stage.welcome => _buildWelcome(),
      _Stage.failed => _buildFailed(),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_stage == _Stage.welcome)
              _Backdrop(
                image: _backgroundImage(context),
                reveal: _reveal,
                drift: _drift,
              ),
            SafeArea(
              child: CustomMultiChildLayout(
                delegate: _SplashLayout(_reveal),
                children: [
                  LayoutId(id: _Slot.mark, child: _buildLockup()),
                  if (content != null)
                    LayoutId(id: _Slot.content, child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The mark with the wordmark beneath it. The wordmark only appears with
  /// the reveal, its letters drifting apart as it fades in.
  Widget _buildLockup() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(
            height: 150,
            busy: _stage == _Stage.loading || _retrying,
            onIntroComplete: _onIntroComplete,
          ),
          const SizedBox(height: 32),
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) {
              final t = const Interval(
                0.3,
                0.8,
                curve: Curves.easeOutCubic,
              ).transform(_reveal.value);
              final spacing = lerpDouble(2, 9, t)!;
              return Opacity(
                opacity: t,
                // Letter spacing trails the last letter too; pad the
                // leading side to match so the word stays centred.
                child: Padding(
                  padding: EdgeInsets.only(left: spacing),
                  child: Text(
                    'RAKAN',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: spacing,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Rise(
            reveal: _reveal,
            interval: const Interval(0.3, 0.75),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Start working out\nyour way.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.08,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Rise(
            reveal: _reveal,
            interval: const Interval(0.4, 0.85),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'A training plan that adapts to your schedule, equipment and recovery.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          _Rise(
            reveal: _reveal,
            interval: const Interval(0.5, 0.95),
            child: ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Get Started',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _Rise(
            reveal: _reveal,
            interval: const Interval(0.6, 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'ALREADY A MEMBER?  ',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Pressable(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'LOG IN',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Rise(
            reveal: _reveal,
            interval: const Interval(0.7, 1),
            child: const FeatureTicker(items: _features),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      child: _Rise(
        reveal: _reveal,
        interval: const Interval(0.35, 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your account",
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              child: _retrying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.onPrimary,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The welcome photo, fading in with the reveal and drifting slowly.
class _Backdrop extends StatelessWidget {
  final ImageProvider image;
  final Animation<double> reveal;
  final Animation<double> drift;

  const _Backdrop({
    required this.image,
    required this.reveal,
    required this.drift,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([reveal, drift]),
      builder: (context, child) {
        final fade = const Interval(
          0.05,
          0.8,
          curve: Curves.easeOut,
        ).transform(reveal.value);
        final zoom = 1.04 + 0.08 * Curves.easeInOut.transform(drift.value);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: zoom,
            alignment: const Alignment(0.3, 0.2),
            child: child,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(image: image, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.surface.withValues(alpha: 0.82),
                  AppColors.surface.withValues(alpha: 0.5),
                  AppColors.surface.withValues(alpha: 0.78),
                  AppColors.surface.withValues(alpha: 0.98),
                ],
                stops: const [0, 0.38, 0.62, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades its child in while lifting it into place, over [interval] of
/// [reveal].
class _Rise extends StatelessWidget {
  final Animation<double> reveal;
  final Interval interval;
  final Widget child;

  const _Rise({
    required this.reveal,
    required this.interval,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(
          interval.transform(reveal.value),
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

enum _Slot { mark, content }

/// Pins the content to the bottom and moves the mark from the centre of the
/// screen (loading) to the centre of the space left above the content.
class _SplashLayout extends MultiChildLayoutDelegate {
  final Animation<double> reveal;

  _SplashLayout(this.reveal) : super(relayout: reveal);

  @override
  void performLayout(Size size) {
    var contentHeight = 0.0;
    if (hasChild(_Slot.content)) {
      contentHeight = layoutChild(
        _Slot.content,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
      ).height;
      positionChild(_Slot.content, Offset(0, size.height - contentHeight));
    }

    final room = (size.height - contentHeight).clamp(0.0, size.height);
    final mark = layoutChild(
      _Slot.mark,
      BoxConstraints.loose(Size(size.width, room)),
    );
    final centred = (size.height - mark.height) / 2;
    final slotted = (room - mark.height) / 2;
    final t = Curves.easeInOutCubic.transform(
      const Interval(0, 0.7).transform(reveal.value),
    );
    positionChild(
      _Slot.mark,
      Offset((size.width - mark.width) / 2, lerpDouble(centred, slotted, t)!),
    );
  }

  @override
  bool shouldRelayout(_SplashLayout oldDelegate) =>
      oldDelegate.reveal != reveal;
}
