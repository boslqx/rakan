import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../../../shared/widgets/main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.manrope()),
        backgroundColor: AppColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signInWithEmail() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
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
      if (result == null) return; // user cancelled
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (_) => false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showError('Enter your email above first');
      return;
    }
    try {
      await _authService.sendPasswordResetEmail(_emailController.text);
      _showSuccess('Password reset email sent');
    } catch (e) {
      _showError(e.toString());
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
            children: [
              const SizedBox(height: 48),

              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLow,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  // Replace with Image.asset('assets/images/logo.png')
                  child: Text(
                    'R',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                'RAKAN',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'HIGH PERFORMANCE AI',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 3,
                  color: AppColors.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 48),

              // Email input
              _AuthLabel('IDENTIFIER'),
              const SizedBox(height: 8),
              _buildInput(
                controller: _emailController,
                hint: 'Email or Username',
                inputType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 24),

              // Password input
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _AuthLabel('ACCESS KEY'),
                  GestureDetector(
                    onTap: _forgotPassword,
                    child: Text(
                      'FORGOT?',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInput(
                controller: _passwordController,
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
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),

              const SizedBox(height: 32),

              // Login button
              ElevatedButton(
                onPressed: _isLoading ? null : _signInWithEmail,
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
                        'LOG IN →',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
              ),

              const SizedBox(height: 32),

              // Connect via divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.outlineVariant,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'CONNECT VIA',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.outlineVariant,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Social buttons
              Row(
                children: [
                  // Google
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : _signInWithGoogle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
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
                            const SizedBox(width: 8),
                            Text(
                              'GMAIL',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Join link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account?  ",
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(
                      'Join Rakan AI',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
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
    bool obscure = false,
    TextInputType inputType = TextInputType.text,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: inputType,
        style: GoogleFonts.manrope(fontSize: 16, color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.manrope(
            fontSize: 16,
            color: AppColors.onSurfaceVariant.withOpacity(0.5),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

// Auth Label widget
class _AuthLabel extends StatelessWidget {
  final String text;
  const _AuthLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
