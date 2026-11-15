import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Shows a photo whole — never cropped — inside a card-width frame.
///
/// The frame takes the photo's own shape, but is never taller than
/// [maxHeightRatio] × its width (4:5 by default, like Instagram). A photo
/// taller than that is fitted inside, with a blurred, darkened copy of
/// itself filling the sides instead of black bars.
///
/// Tapping opens [FullScreenPhoto] with pinch-to-zoom.
class PhotoFrame extends StatefulWidget {
  final ImageProvider image;

  /// Tallest the frame may be, as a multiple of its width.
  final double maxHeightRatio;

  /// Height of the slot shown while the photo's size is not yet known.
  final double placeholderHeight;
  final double borderRadius;
  final bool tapToExpand;

  const PhotoFrame({
    super.key,
    required this.image,
    this.maxHeightRatio = 1.25,
    this.placeholderHeight = 220,
    this.borderRadius = 16,
    this.tapToExpand = true,
  });

  @override
  State<PhotoFrame> createState() => _PhotoFrameState();
}

class _PhotoFrameState extends State<PhotoFrame> {
  /// Width / height of photos already measured, so scrolling a card back
  /// into view doesn't flash the placeholder again.
  // Map literals keep insertion order, so the first key is the oldest.
  static final _aspectCache = <ImageProvider, double>{};
  static const _aspectCacheLimit = 100;

  double? _aspect;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PhotoFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  /// Reads the photo's pixel size through the normal image cache, so the
  /// decode is shared with the [Image] widgets that draw it.
  void _resolve() {
    _stopListening();
    _failed = false;
    _aspect = _aspectCache[widget.image];
    if (_aspect != null) return;

    final image = widget.image;
    final stream = image.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final aspect = info.image.width / info.image.height;
        info.dispose();
        _aspectCache[image] = aspect;
        if (_aspectCache.length > _aspectCacheLimit) {
          _aspectCache.remove(_aspectCache.keys.first);
        }
        _stopListening();
        if (mounted && image == widget.image) setState(() => _aspect = aspect);
      },
      onError: (_, _) {
        _stopListening();
        if (mounted && image == widget.image) setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => FullScreenPhoto(image: widget.image),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();

    final radius = BorderRadius.circular(widget.borderRadius);
    final aspect = _aspect;
    if (aspect == null) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          width: double.infinity,
          height: widget.placeholderHeight,
          color: AppColors.surfaceContainerHigh,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final minAspect = 1 / widget.maxHeightRatio;
        // Taller than the frame allows → fit inside and fill the sides.
        final needsFill = aspect < minAspect;
        final height = width / (needsFill ? minAspect : aspect);

        Widget frame = ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (needsFill) ...[
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Image(image: widget.image, fit: BoxFit.cover),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                ],
                Image(
                  image: widget.image,
                  fit: needsFill ? BoxFit.contain : BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );

        if (widget.tapToExpand) {
          frame = GestureDetector(onTap: _openFullScreen, child: frame);
        }
        return frame;
      },
    );
  }
}

/// A photo on a black screen with pinch-to-zoom and a close button.
class FullScreenPhoto extends StatelessWidget {
  final ImageProvider image;

  const FullScreenPhoto({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image(image: image, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                ),
                tooltip: 'Close',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
