/// Centralised validation rules for the app
class Validators {
  Validators._(); 

  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');

  static final RegExp _hasLower = RegExp(r'[a-z]');
  static final RegExp _hasUpper = RegExp(r'[A-Z]');
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasSymbol = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]');


  /// One requirement in the password strength checklist
  static final List<PasswordRequirement> passwordRequirements = [
    PasswordRequirement('At least 8 characters', (v) => v.length >= 8),
    PasswordRequirement('One lowercase letter', (v) => _hasLower.hasMatch(v)),
    PasswordRequirement('One uppercase letter', (v) => _hasUpper.hasMatch(v)),
    PasswordRequirement('One number', (v) => _hasDigit.hasMatch(v)),
    PasswordRequirement('One symbol (!, @, #, ...)', (v) => _hasSymbol.hasMatch(v)),
  ];

  /// Email format check. Used identically on login and register
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Login password: presence only 
  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  /// Registration password: valid only if every checklist requirement
  /// is met. The checklist widget reads `passwordRequirements` directly
  /// for live per-rule display — this method is just the form-level
  /// pass/fail gate used on submit.
  static String? registerPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    final allMet = passwordRequirements.every((r) => r.test(v));
    return allMet ? null : 'Password does not meet all requirements';
  }

  /// Confirm-password match check.
  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }
}

/// Added at the bottom of the file (outside Validators)
class PasswordRequirement {
  final String label;
  final bool Function(String value) test;
  
  const PasswordRequirement(this.label, this.test);
}