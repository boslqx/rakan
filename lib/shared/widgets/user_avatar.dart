import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

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
    Uint8List? bytes;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(photoBase64!);
      } catch (_) {
        // Corrupted/invalid data — fail closed to the initials
        // fallback rather than crashing the whole avatar render.
        bytes = null;
      }
    }

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
              errorBuilder: (_, __, ___) => _initials(),
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