import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/models/onboarding_data.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../onboarding/widgets/equipment_selector.dart';

class EditEquipmentScreen extends StatefulWidget {
  const EditEquipmentScreen({super.key});

  @override
  State<EditEquipmentScreen> createState() => _EditEquipmentScreenState();
}

class _EditEquipmentScreenState extends State<EditEquipmentScreen> {
  final _profileService = UserProfileService();

  Set<EquipmentType> _saved = {};   // what's currently in Firestore
  Set<EquipmentType> _pending = {}; // what the user has selected on-screen
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final profile = await _profileService.getUserProfile(uid);
    final raw = profile?['equipment'] as List<dynamic>?;
    final parsed = OnboardingData.equipmentFromNames(raw);

    if (!mounted) return;
    setState(() {
      _saved = parsed;
      _pending = Set<EquipmentType>.from(parsed);
      _isLoading = false;
    });
  }

  // Only enable Save once something has actually changed 
  bool get _hasChanges =>
      _pending.length != _saved.length || !_pending.containsAll(_saved);

  Future<void> _save() async {
    if (_pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one equipment option',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      await _profileService.updateEquipment(uid: uid, equipment: _pending);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Equipment updated. This applies to your next plan reset '
            'or template workout — your current plan is unchanged.',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save equipment — please try again',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        title: Text(
          'EQUIPMENT',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'What equipment do you have access to?',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Changes apply the next time a plan is generated or '
                    'a workout day is built from a template. Your '
                    'current active plan is not modified.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 24),

                  EquipmentSelector(
                    initialSelection: _pending,
                    onChanged: (selected) {
                      setState(() => _pending = selected);
                    },
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: (_hasChanges && !_isSaving) ? _save : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(
                            'SAVE CHANGES',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}