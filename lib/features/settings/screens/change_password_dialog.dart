import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';

class ChangePasswordDialog {
  static Future<void> show(BuildContext context) async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isLoading = false;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Change Password',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your current password and choose a new one.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: currentPasswordController,
                    label: 'Current Password',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: newPasswordController,
                    label: 'New Password',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: confirmPasswordController,
                    label: 'Confirm New Password',
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        // Validation
                        final current = currentPasswordController.text;
                        final newPass = newPasswordController.text;
                        final confirm = confirmPasswordController.text;

                        if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                          setState(() => errorText = 'All fields are required');
                          return;
                        }
                        if (newPass.length < 6) {
                          setState(() => errorText = 'New password must be at least 6 characters');
                          return;
                        }
                        if (newPass != confirm) {
                          setState(() => errorText = 'Passwords do not match');
                          return;
                        }

                        setState(() {
                          isLoading = true;
                          errorText = null;
                        });

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null || user.email == null) {
                            throw Exception('No signed-in user found');
                          }

                          // Re-authenticate
                          final credential = EmailAuthProvider.credential(
                            email: user.email!,
                            password: current,
                          );
                          await user.reauthenticateWithCredential(credential);

                          // Step 2: Update password
                          await user.updatePassword(newPass);

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Password updated successfully',
                                  style: GoogleFonts.manrope(color: AppColors.onSurface),
                                ),
                                backgroundColor: AppColors.surfaceContainerHigh,
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setState(() {
                            isLoading = false;
                            errorText = _friendlyError(e.code);
                          });
                        } catch (e) {
                          setState(() {
                            isLoading = false;
                            errorText = 'Something went wrong. Try again.';
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(
                        'UPDATE',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.manrope(
          fontSize: 13,
          color: AppColors.onSurfaceVariant,
        ),
        filled: true,
        fillColor: AppColors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  /// Converts Firebase error codes into human-readable messages.
  static String _friendlyError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect';
      case 'weak-password':
        return 'New password is too weak';
      case 'requires-recent-login':
        return 'Please log out and log back in, then try again';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      default:
        return 'Error: $code';
    }
  }
}