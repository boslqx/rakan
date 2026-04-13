import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/main_shell.dart';

class RakanApp extends StatelessWidget {
  const RakanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rakan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}