import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../services/auth_service.dart';
import '../../onboarding/screens/onboarding_shell.dart';
import '../../../shared/widgets/main_shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../features/onboarding/services/user_profile_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  String? _emailError;
  String? _confirmError;
  // Password field itself uses the live checklist
  bool _passwordValid = false;

  bool _emailTouched = false;
  bool _confirmTouched = false;
  bool _passwordHasContent = false; // controls checklist visibility

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) _validateEmail(force: true);
    });
    _confirmFocus.addListener(() {
      if (!_confirmFocus.hasFocus) _validateConfirm(force: true);
    });
    // If the user edits password after already filling confirm,
    // re-check the match live so a stale "match" error doesn't linger.
    _passwordController.addListener(() {
      setState(() {
        _passwordHasContent = _passwordController.text.isNotEmpty;
        _passwordValid =
            Validators.registerPassword(_passwordController.text) == null;
      });
      if (_confirmTouched) _validateConfirm();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _validateEmail({bool force = false}) {
    if (!_emailTouched && !force) return;
    setState(() {
      _emailTouched = true;
      _emailError = Validators.email(_emailController.text);
    });
  }

  void _validateConfirm({bool force = false}) {
    if (!_confirmTouched && !force) return;
    setState(() {
      _confirmTouched = true;
      _confirmError = Validators.confirmPassword(
        _confirmController.text,
        _passwordController.text,
      );
    });
  }

  bool _validateAll() {
    setState(() {
      _emailTouched = true;
      _confirmTouched = true;
      _emailError = Validators.email(_emailController.text);
      _confirmError = Validators.confirmPassword(
        _confirmController.text,
        _passwordController.text,
      );
      _passwordValid =
          Validators.registerPassword(_passwordController.text) == null;
    });
    return _emailError == null && _confirmError == null && _passwordValid;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.manrope()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _registerWithEmail() async {
    if (!_validateAll()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingShell()),
        (_) => false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (result == null) return;
      if (!mounted) return;
      await _routeAfterLogin();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeAfterLogin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final hasProfile = await UserProfileService().hasCompletedOnboarding(uid);
    if (!mounted) return;

    if (hasProfile) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (_) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingShell()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

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
                  GestureDetector(
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
                'JOIN THE\nELITE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'PRECISION INTELLIGENCE FOR HUMAN PERFORMANCE',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 32),

              // Social auth section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _isLoading ? null : _signInWithGoogle,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(48),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'G',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'CONTINUE WITH GOOGLE',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SECURE END-TO-END ENCRYPTED\nAUTHENTICATION PROTOCOLS.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Email/Password section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AuthLabel('EMAIL'),
                    const SizedBox(height: 8),
                    _buildInput(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      hint: 'name@domain.com',
                      inputType: TextInputType.emailAddress,
                      errorText: _emailError,
                      onChanged: (_) => _validateEmail(),
                    ),

                    const SizedBox(height: 20),

                    _AuthLabel('ACCESS CREDENTIALS'),
                    const SizedBox(height: 8),
                    _buildInput(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      hint: '••••••••',
                      obscure: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),

                    // Live checklist — only shown once the user starts
                    if (_passwordHasContent) ...[
                      const SizedBox(height: 10),
                      _PasswordChecklist(password: _passwordController.text),
                    ],

                    const SizedBox(height: 20),

                    _AuthLabel('CONFIRM PASSWORD'),
                    const SizedBox(height: 8),
                    _buildInput(
                      controller: _confirmController,
                      focusNode: _confirmFocus,
                      hint: '••••••••',
                      obscure: _obscureConfirm,
                      errorText: _confirmError,
                      onChanged: (_) => _validateConfirm(),
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _isLoading ? null : _registerWithEmail,
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Text(
                              'INITIALIZE ACCOUNT',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: AppColors.onSurfaceVariant.withOpacity(0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '256-BIT ENCRYPTED JOURNEY',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    FocusNode? focusNode,
    bool obscure = false,
    TextInputType inputType = TextInputType.text,
    Widget? suffix,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: errorText != null ? AppColors.error : AppColors.outlineVariant,
        ),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: inputType,
        onChanged: onChanged,
        style: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.manrope(
            fontSize: 15,
            color: AppColors.onSurfaceVariant.withOpacity(0.4),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: suffix,
          errorText: errorText,
          errorStyle: GoogleFonts.manrope(fontSize: 12, color: AppColors.error),
          errorMaxLines: 2,
        ),
      ),
    );
  }
}

/// Live password-strength checklist
class _PasswordChecklist extends StatelessWidget {
  final String password;
  const _PasswordChecklist({required this.password});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: Validators.passwordRequirements.map((req) {
        final met = req.test(password);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                met ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: met ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                req.label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: met ? AppColors.onSurface : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AuthLabel extends StatelessWidget {
  final String text;
  const _AuthLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}