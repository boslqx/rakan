import 'package:flutter/material.dart';
import 'package:rakan/core/theme/app_colors.dart';
import 'bottom_nav_bar.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/coach/screens/coach_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/workout/screens/workout_screen.dart';

class MainShell extends StatefulWidget{
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // All 4 screens live here
  final List<Widget> _screens = [
    const HomeScreen(),
    const WorkoutScreen(),
    const CoachScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBright,
      // When switching tabs, we keep the state of each screen alive using IndexedStack
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: RakanBottomNavBar(
        currentIndex: _currentIndex, 
        onTap: (onTap) {
          setState(() {
            _currentIndex = onTap;
          });
        }
      ),
    );
  }
}