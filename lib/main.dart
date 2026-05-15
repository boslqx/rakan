import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  // Step 1: Wake up Flutter's native bridge 
  WidgetsFlutterBinding.ensureInitialized();

  // Step 2: Connect to Firebase using the auto-generated config
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Step 3: render the app
  runApp(const RakanApp());
}