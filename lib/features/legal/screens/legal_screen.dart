import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pressable.dart';
import '../data/legal_content.dart';

/// Read-only page for the Terms & Conditions or Privacy Policy.
class LegalScreen extends StatelessWidget {
  final LegalDocumentContent document;
  const LegalScreen({super.key, required this.document});

  static Future<void> open(BuildContext context, LegalDocumentContent document) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalScreen(document: document)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RAKAN AI',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.onSurface,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Text(
              document.title.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'LAST UPDATED ${document.lastUpdated.toUpperCase()}',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 24),

            Text(
              document.intro,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.onSurface,
                height: 1.6,
              ),
            ),

            for (final section in document.sections) ...[
              const SizedBox(height: 24),
              Text(
                section.heading,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section.body,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
