import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import 'pose_detection_screen.dart';

class ExerciseDetailSheet extends StatefulWidget {
  final ExerciseData exercise;

  const ExerciseDetailSheet({super.key, required this.exercise});

  @override
  State<ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<ExerciseDetailSheet> {
  late final WebViewController _webController;
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    // Use embedded YouTube player with minimal UI for better mobile experience
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0c0e10; }
    .wrapper {
      position: relative;
      width: 100%;
      padding-bottom: 56.25%;
      height: 0;
      overflow: hidden;
    }
    iframe {
      position: absolute;
      top: 0; left: 0;
      width: 100%; height: 100%;
      border: none;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <iframe
      src="https://www.youtube.com/embed/${widget.exercise.youtubeId}?rel=0&modestbranding=1&playsinline=1"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
      allowfullscreen>
    </iframe>
  </div>
</body>
</html>
''';

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _videoLoaded = true);
        },
      ))
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Video player
                  _buildVideoPlayer(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Difficulty + category badges
                        Row(
                          children: [
                            _buildBadge(widget.exercise.difficulty),
                            const SizedBox(width: 8),
                            _buildBadge(widget.exercise.muscleGroup),
                            if (widget.exercise.hasPoseDetection) ...[
                              const SizedBox(width: 8),
                              _buildBadge('AI Form Check',
                                  highlight: true),
                            ],
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Exercise name
                        Text(
                          widget.exercise.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                            height: 1.1,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Equipment
                        Row(
                          children: [
                            const Icon(Icons.fitness_center_rounded,
                                size: 13,
                                color: AppColors.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              widget.exercise.equipment,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Target anatomy
                        _buildSectionTitle('TARGET ANATOMY'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Primary muscle is always first
                            _buildMuscleChip(
                                widget.exercise.muscleGroup,
                                isPrimary: true),
                            ...widget.exercise.secondaryMuscles
                                .map((m) => _buildMuscleChip(m)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Sets / reps guide
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.repeat_rounded,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RECOMMENDED VOLUME',
                                    style: GoogleFonts.manrope(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.exercise.setsRepsGuide,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Step-by-step instructions
                        _buildSectionTitle('STEP-BY-STEP'),
                        const SizedBox(height: 12),
                        ...widget.exercise.steps.asMap().entries.map(
                              (entry) => _buildStep(
                                  entry.key + 1, entry.value),
                            ),

                        const SizedBox(height: 24),

                        // Tips
                        _buildTipsCard(),

                        // Pose detection CTA
                        if (widget.exercise.hasPoseDetection) ...[
                          const SizedBox(height: 24),
                          _buildFormCheckButton(context),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Video player with loading state
  Widget _buildVideoPlayer() {
    return SizedBox(
      // 16:9 aspect ratio for video
      height: MediaQuery.of(context).size.width * 9 / 16,
      child: Stack(
        children: [
          WebViewWidget(controller: _webController),
          // Loading shimmer shown until page finishes loading
          if (!_videoLoaded)
            Container(
              color: AppColors.surfaceContainerHigh,
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helpers 
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildBadge(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(48),
        border: highlight
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: highlight ? AppColors.primary : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMuscleChip(String label, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(48),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isPrimary
              ? AppColors.primary
              : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number circle
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'FORM TIPS',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...widget.exercise.tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCheckButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context); // Close the sheet
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PoseDetectionScreen(
              exerciseName: widget.exercise.name,
              targetReps: 10,
            ),
          ),
        );
      },
      icon: const Icon(Icons.camera_alt_rounded, size: 18),
      label: Text(
        'TRY WITH FORM CHECK →',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}