import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../legal/data/legal_content.dart';
import '../../legal/screens/legal_screen.dart';
import '../../legal/services/legal_consent_service.dart';
import '../services/auth_service.dart';
import 'email_verification_screen.dart';
import '../services/auth_navigation_service.dart'; 
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/password_checklist.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Lazy so the form can be built (and widget-tested) without Firebase.
  late final AuthService _authService = AuthService();

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

  // Must be ticked before the account is created — by email (and so before
  // the verification email goes out) or with Google.
  bool _agreedToTerms = false;
  bool _termsError = false;
  final GlobalKey _termsKey = GlobalKey();
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => LegalScreen.open(context, termsAndConditions);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => LegalScreen.open(context, privacyPolicy);
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
    _termsTap.dispose();
    _privacyTap.dispose();
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
      _termsError = !_agreedToTerms;
    });
    return _emailError == null &&
        _confirmError == null &&
        _passwordValid &&
        _agreedToTerms;
  }

  void _setAgreedToTerms(bool value) {
    setState(() {
      _agreedToTerms = value;
      if (value) _termsError = false;
    });
  }

  /// Google sign-up sits above the checkbox, so flag it and scroll it
  /// into view rather than failing silently.
  void _promptForTerms() {
    setState(() => _termsError = true);
    final termsContext = _termsKey.currentContext;
    if (termsContext != null) {
      Scrollable.ensureVisible(
        termsContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _showError(
      'Please agree to the Terms & Conditions and Privacy Policy first.',
    );
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
        final credential = await _authService.signUpWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        final uid = credential?.user?.uid;
        if (uid != null) {
          // Unverified, so it's written later with the onboarding profile.
          await LegalConsentService()
              .recordAcceptance(uid: uid, canWriteNow: false);
        }
        if (!mounted) return;
        // Verification email is sent by EmailVerificationScreen on open.
        // New email/password accounts always go to the verification
        // gate first — never straight to onboarding.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
          (_) => false,
        );
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

    Future<void> _signInWithGoogle() async {
      if (!_agreedToTerms) {
        _promptForTerms();
        return;
      }
      setState(() => _isLoading = true);
      try {
        final result = await _authService.signInWithGoogle();
        if (result == null) return;
        final user = result.user;
        if (user != null) {
          await LegalConsentService()
              .recordAcceptance(uid: user.uid, canWriteNow: true);
        }
        if (!mounted) return;
        final next = await AuthNavigationService().resolveNextScreen();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => next),
          (_) => false,
        );
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AutofillGroup(
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
                  Pressable(
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
                    Pressable(
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
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
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
                      autofillHints: const [AutofillHints.newUsername],
                      action: TextInputAction.next,
                      onSubmit: () => _passwordFocus.requestFocus(),
                    ),

                    const SizedBox(height: 20),

                    _AuthLabel('ACCESS CREDENTIALS'),
                    const SizedBox(height: 8),
                    _buildInput(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      hint: '••••••••',
                      obscure: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      action: TextInputAction.next,
                      onSubmit: () => _confirmFocus.requestFocus(),
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
                      PasswordChecklist(password: _passwordController.text),
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
                      autofillHints: const [AutofillHints.newPassword],
                      action: TextInputAction.done,
                      onSubmit: _isLoading ? null : _registerWithEmail,
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

                    const SizedBox(height: 20),

                    _buildTermsCheckbox(),

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
                child: Text(
                  "We'll email you a link to verify your address.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text.rich(
                    TextSpan(
                      text: 'Already have an account?  ',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '256-BIT ENCRYPTED JOURNEY',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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
      ),
    );
  }

  Widget _buildTermsCheckbox() {
    final linkStyle = GoogleFonts.manrope(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.onSurface,
    );

    return Column(
      key: _termsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tapping the sentence toggles the box; the two links open the
        // documents instead (their recognizers win the gesture arena).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isLoading ? null : () => _setAgreedToTerms(!_agreedToTerms),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _agreedToTerms,
                  onChanged: _isLoading
                      ? null
                      : (v) => _setAgreedToTerms(v ?? false),
                  activeColor: AppColors.primary,
                  checkColor: AppColors.onPrimary,
                  side: BorderSide(
                    color: _termsError
                        ? AppColors.error
                        : AppColors.onSurfaceVariant,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terms & Conditions',
                          style: linkStyle,
                          recognizer: _termsTap,
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: linkStyle,
                          recognizer: _privacyTap,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_termsError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              'Please agree to continue',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ],
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
    Iterable<String>? autofillHints,
    TextInputAction? action,
    VoidCallback? onSubmit,
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
        autofillHints: autofillHints,
        textInputAction: action,
        onFieldSubmitted: (_) => onSubmit?.call(),
        autocorrect: false,
        enableSuggestions: !obscure,
        inputFormatters: [LengthLimitingTextInputFormatter(128)],
        style: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.manrope(
            fontSize: 15,
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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