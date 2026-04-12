import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/home/screens/home_screen.dart';

class RakanApp extends StatelessWidget {
  const RakanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rakan',
      debugShowCheckedModeBanner: false, // removes the red DEBUG banner
      theme: AppTheme.darkTheme,        // applying our design system
      home: const HomeScreen(),
    );
  }
}