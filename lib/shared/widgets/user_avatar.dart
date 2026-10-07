import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../utils/base64_image_cache.dart';

/// Single source of truth for rendering a user's avatar
class UserAvatar extends StatelessWidget {
  /// Base64-encoded JPEG bytes, or null/empty if no photo is set.
  final String? photoBase64;

  /// Display name or email — first character is used for the
  /// fallback initial when there's no photo.
  final String initialsSource;

  final double size;

  const UserAvatar({
    super.key,
    required this.photoBase64,
    required this.initialsSource,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    // Decoded once and cached (see Base64ImageCache) instead of on every
    // rebuild. Corrupted data returns null, falling back to the initials.
    final Uint8List? bytes = Base64ImageCache.decode(photoBase64);

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _initials(),
            )
          : _initials(),
    );
  }

  Widget _initials() {
    final letter =
        initialsSource.isNotEmpty ? initialsSource[0].toUpperCase() : 'R';
    return Center(
      child: Text(
        letter,
        style: GoogleFonts.spaceGrotesk(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}