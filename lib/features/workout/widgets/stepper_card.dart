import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/pressable.dart';

/// A value with −/+ either side; tap the value itself for exact entry when
/// [onTapValue] is given.
class StepperCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapValue;

  const StepperCard({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              StepButton(icon: Icons.remove_rounded, onTap: onMinus),
              Expanded(
                child: Pressable(
                  onTap: onTapValue,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              StepButton(icon: Icons.add_rounded, onTap: onPlus),
            ],
          ),
        ],
      ),
    );
  }
}

class StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const StepButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.white10,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}
