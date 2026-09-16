import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import 'exercise_detail_sheet.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  // Filter state
  String _selectedMuscle = MuscleGroups.all;
  String _selectedDifficulty = 'All';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<String> _difficultyFilters = [
    'All',
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filtered list — computed on every build based on current filter state
  List<ExerciseData> get _filtered {
    return kExercises.where((ex) {
      final matchesMuscle =
          _selectedMuscle == MuscleGroups.all ||
          ex.muscleGroup == _selectedMuscle;
      final matchesDifficulty =
          _selectedDifficulty == 'All' || ex.difficulty == _selectedDifficulty;
      final matchesSearch =
          _searchQuery.isEmpty ||
          ex.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          ex.muscleGroup.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesMuscle && matchesDifficulty && matchesSearch;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _selectedMuscle != MuscleGroups.all ||
      _selectedDifficulty != 'All' ||
      _searchQuery.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _selectedMuscle = MuscleGroups.all;
      _selectedDifficulty = 'All';
      _searchQuery = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercises = _filtered;

    // Everything — search bar, filter chips, result count, and the grid —
    // lives in one CustomScrollView so the whole section scrolls as a
    // single unit (instead of only the grid scrolling under a static
    // header), filling all the way down to just above the bottom nav bar.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildSearchBar()),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(child: _buildMuscleFilterRow()),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverToBoxAdapter(child: _buildDifficultyFilterRow()),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(child: _buildResultCountRow(exercises.length)),
        if (exercises.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmpty())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // Slightly taller than square to fit name + dots
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ExerciseCard(exercise: exercises[i]),
                childCount: exercises.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: 'Search exercises...',
            hintStyle: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.onSurfaceVariant,
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.onSurfaceVariant,
                      size: 18,
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMuscleFilterRow() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: MuscleGroups.filters.length,
        itemBuilder: (_, i) {
          final group = MuscleGroups.filters[i];
          final isSelected = _selectedMuscle == group;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedMuscle = group),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Text(
                  group,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.onPrimary
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDifficultyFilterRow() {
    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _difficultyFilters.length,
        itemBuilder: (_, i) {
          final diff = _difficultyFilters[i];
          final isSelected = _selectedDifficulty == diff;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedDifficulty = diff),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  diff,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultCountRow(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: [
          Text(
            '$count EXERCISE${count == 1 ? '' : 'S'}',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (_hasActiveFilters) ...[
            const Spacer(),
            GestureDetector(
              onTap: _clearFilters,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CLEAR FILTERS',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: AppColors.onSurfaceVariant,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No exercises found',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search or filter',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _clearFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: Text(
                    'CLEAR FILTERS',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Exercise card
class _ExerciseCard extends StatelessWidget {
  final ExerciseData exercise;

  const _ExerciseCard({required this.exercise});

  @override
  Widget _buildThumbnail() {
    // Case 1: local static thumbnail from the curated GIF set
    if (exercise.thumbnailAsset != null) {
      return Image.asset(
        exercise.thumbnailAsset!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbnailPlaceholder(),
      );
    }

    // Case 2: no local thumbnail, but a real YouTube ID
    if (exercise.youtubeId.isNotEmpty) {
      return Image.network(
        'https://img.youtube.com/vi/${exercise.youtubeId}/mqdefault.jpg',
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppColors.surfaceContainerHigh,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.primary,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _thumbnailPlaceholder(),
      );
    }

    // Case 3: neither — icon placeholder
    return _thumbnailPlaceholder();
  }

  Widget _thumbnailPlaceholder() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: const Center(
        child: Icon(
          Icons.fitness_center_rounded,
          color: AppColors.onSurfaceVariant,
          size: 28,
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail area with muscle badge
            Expanded(
              child: Stack(
                children: [
                  // YouTube thumbnail — loaded from YouTube's CDN
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: _buildThumbnail(),
                  ),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.surfaceContainerLow.withValues(
                              alpha: 0.7,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Muscle group badge — top right
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        exercise.muscleGroup.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),

                  // Pose detection badge — top left
                  if (exercise.hasPoseDetection)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 10,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Name + difficulty dots
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Difficulty dots
                      ..._difficultyDots(exercise.difficulty),
                      const SizedBox(width: 6),
                      Text(
                        exercise.difficulty.toUpperCase().substring(0, 3),
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _difficultyDots(String difficulty) {
    final filled = difficulty == 'Beginner'
        ? 1
        : difficulty == 'Intermediate'
        ? 2
        : 3;

    return List.generate(3, (i) {
      return Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < filled
                ? AppColors.primary
                : AppColors.surfaceContainerHigh,
          ),
        ),
      );
    });
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ExerciseDetailSheet(exercise: exercise),
    );
  }
}
