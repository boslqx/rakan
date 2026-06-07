import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/widgets/main_shell.dart';
import '../services/adapt_service.dart';

class WorkoutCompleteScreen extends StatefulWidget {
  final String workoutName;
  final int durationMins;
  final double totalVolume;
  final int exerciseCount;
  final String uid;
  final double avgRpe;
  final double maxRpe;
  final double completionRate;
  final List<Map<String, dynamic>> exerciseLogs; // ← NEW
  final String logId;                             // ← NEW

  const WorkoutCompleteScreen({
    super.key,
    required this.workoutName,
    required this.durationMins,
    required this.totalVolume,
    required this.exerciseCount,
    required this.uid,
    required this.avgRpe,
    required this.maxRpe,
    required this.completionRate,
    required this.exerciseLogs,
    required this.logId,
  });

  @override
  State<WorkoutCompleteScreen> createState() => _WorkoutCompleteScreenState();
}

class _WorkoutCompleteScreenState extends State<WorkoutCompleteScreen> {
  // ── Adaptation state ────────────────────────────────────────────────
  String _adaptStatus = 'loading';
  String _adaptMessage = '';

  // ── Photo state ──────────────────────────────────────────────────────
  File? _selectedPhoto;
  bool _isUploadingPhoto = false;
  bool _photoSaved = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _runAdaptation();
  }

  // ── Adaptation ───────────────────────────────────────────────────────

  Future<void> _runAdaptation() async {
    try {
      final message = await AdaptService().predictAndAdapt(
        uid: widget.uid,
        avgRpe: widget.avgRpe,
        maxRpe: widget.maxRpe,
        sessionDuration: widget.durationMins.toDouble(),
        exercisesCount: widget.exerciseCount,
        completionRate: widget.completionRate,
      );
      if (!mounted) return;
      setState(() {
        _adaptStatus = 'done';
        _adaptMessage = message.isNotEmpty ? message : _buildAdaptMessage();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _adaptStatus = 'error');
    }
  }

  String _buildAdaptMessage() {
    if (widget.avgRpe > 7.5) return '🔄 Next workout adjusted for recovery';
    if (widget.avgRpe < 4.0) return '📈 Next workout intensity increased';
    return '✅ Plan stays on track';
  }

  // ── Photo logic ──────────────────────────────────────────────────────

  /// Shows a bottom sheet to choose camera or gallery.
  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ADD PROGRESS PHOTO',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildPhotoOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              _buildPhotoOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Picks photo, compresses it, saves base64 to Firestore.
  ///
  /// WHY compress? Firestore document limit is 1MB. A raw phone photo
  /// is 3–10MB. We compress to ≤200KB so it fits comfortably, leaving
  /// room for other fields in the document.
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1080,  // Reasonable display resolution
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);

      // Compress further using flutter_image_compress
      // Target: ≤200KB (200,000 bytes), JPEG format
      final compressed = await FlutterImageCompress.compressWithFile(
        picked.path,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      if (compressed == null) {
        setState(() => _isUploadingPhoto = false);
        return;
      }

      // Convert bytes to base64 string for Firestore storage
      final base64String = base64Encode(compressed);

      // Save base64 string to the workout log document in Firestore
      // Path: users/{uid}/workoutLogs/{logId}
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('workoutLogs')
          .doc(widget.logId)
          .update({'progressPhotoBase64': base64String});

      if (!mounted) return;
      setState(() {
        _selectedPhoto = File(picked.path);
        _isUploadingPhoto = false;
        _photoSaved = true;
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save photo. Try again.',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeroSection()),
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverToBoxAdapter(child: _buildAdaptBanner()),
            SliverToBoxAdapter(child: _buildPhotoSection()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  'EXERCISES COMPLETED',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildExerciseLogCard(widget.exerciseLogs[index]),
                childCount: widget.exerciseLogs.length,
              ),
            ),
            SliverToBoxAdapter(child: _buildBottomButton()),
          ],
        ),
      ),
    );
  }

  // ── Hero section ─────────────────────────────────────────────────────

  Widget _buildHeroSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          // Trophy icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.12),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppColors.primary,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'WORKOUT COMPLETE',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.workoutName.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            _buildStat('DURATION', '${widget.durationMins}', 'MIN'),
            _buildDivider(),
            _buildStat(
                'VOLUME', widget.totalVolume.toStringAsFixed(0), 'KG'),
            _buildDivider(),
            _buildStat('EXERCISES', '${widget.exerciseCount}', 'DONE'),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, String unit) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            unit,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 9,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 48,
      color: AppColors.outlineVariant,
    );
  }

  // ── Adapt banner ─────────────────────────────────────────────────────

  Widget _buildAdaptBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: () {
        if (_adaptStatus == 'loading') {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Analysing your performance...',
                style: GoogleFonts.manrope(
                    fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          );
        }
        if (_adaptStatus == 'done') {
          return Center(
            child: Text(
              _adaptMessage,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      }(),
    );
  }

  // ── Photo section ────────────────────────────────────────────────────

  Widget _buildPhotoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROGRESS PHOTO',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),

          // If photo is selected, show preview; otherwise show add button
          if (_selectedPhoto != null)
            _buildPhotoPreview()
          else
            _buildAddPhotoButton(),
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: _isUploadingPhoto ? null : _showPhotoOptions,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.outlineVariant.withOpacity(0.4),
          ),
        ),
        child: _isUploadingPhoto
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.onSurfaceVariant,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ADD PROGRESS PHOTO',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Optional — saved to your log',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            _selectedPhoto!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        // Saved badge
        if (_photoSaved)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(48),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'SAVED',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Change photo button
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: _showPhotoOptions,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(48),
              ),
              child: Text(
                'CHANGE',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Exercise log cards ───────────────────────────────────────────────

  Widget _buildExerciseLogCard(Map<String, dynamic> log) {
    final name = log['exerciseName'] as String? ?? '';
    final muscle = log['muscleGroup'] as String? ?? '';
    final rpe = log['rpeScale'] as int? ?? 0;
    final setDetails =
        (log['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final completedSets =
        setDetails.where((s) => s['completed'] == true).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        muscle.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // RPE badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _rpeColor(rpe).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: Text(
                    'RPE $rpe',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _rpeColor(rpe),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            if (completedSets.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Set chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: completedSets.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final reps = s['reps'] as int? ?? 0;
                  final kg = (s['weightKg'] as num?)?.toDouble() ?? 0;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      // e.g. "S1  10 × 60kg" or "S1  10 reps" if no weight
                      kg > 0
                          ? 'S${i + 1}  $reps × ${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1)}kg'
                          : 'S${i + 1}  $reps reps',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns a colour that reflects effort level — used for RPE badge.
  /// Green = easy, amber = moderate, red = hard.
  /// Academically grounded: RPE zones from Borg Scale literature.
  Color _rpeColor(int rpe) {
    if (rpe <= 4) return const Color(0xFF4CAF50); // Green — easy
    if (rpe <= 7) return const Color(0xFFFFA726); // Amber — moderate
    return AppColors.error;                        // Red — hard
  }

  // ── Bottom button ────────────────────────────────────────────────────

  Widget _buildBottomButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()),
            (_) => false,
          );
        },
        child: Text(
          'BACK TO HOME →',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}