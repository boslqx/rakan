import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

class RakanBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const RakanBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Glassmorphism effect from design.md
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withOpacity(0.15),
            width: 1,
          ),
        ),
      ),

      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Dashboard icon
              _NavItem(              
                icon: Icons.grid_view_rounded,
                label: 'Dashboard',
                isSelected: currentIndex == 0,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(0);
                },
              ),
              
              // Plan Schedule Icon
              _NavItem(
                icon: Icons.calendar_month_rounded,
                label: 'Schedule',
                isSelected: currentIndex == 1,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(1);
                },
              ),

              // Coach Icon
              _NavItem(
                icon: Icons.auto_awesome_rounded,
                label: 'Coach',
                isSelected: currentIndex == 2,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(2);
                },
              ),

              // Settings Icon
              _NavItem(
                icon: Icons.settings_rounded ,
                label: 'Settings',
                isSelected: currentIndex == 3,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(3);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Private widget for this file
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
