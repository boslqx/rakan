import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';

class Step4Preference extends StatelessWidget {
  final OnboardingData data;
  final VoidCallback onNext;
  const Step4Preference({super.key, required this.data, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          ElevatedButton(
            onPressed: onNext,
            child: const Text('CONTINUE >'),
          ),
        ],
      ),
    );
  }
}