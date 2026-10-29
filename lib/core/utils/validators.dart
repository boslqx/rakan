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

  // Body stats, shared by onboarding and Settings → Personal Stats (V-21).
  // Age matches the onboarding picker (13–80; the Terms require 13+);
  // height and weight only catch typos (e.g. 1750 cm, 7 kg).
  static const int minAge = 13;
  static const int maxAge = 80;
  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;
  static const double minWeightKg = 30;
  static const double maxWeightKg = 300;

  static String? age(int? value) {
    if (value == null) return 'Enter your age';
    if (value < minAge || value > maxAge) {
      return 'Age must be between $minAge and $maxAge';
    }
    return null;
  }

  static String? heightCm(double? value) {
    if (value == null) return 'Enter your height';
    if (value < minHeightCm || value > maxHeightCm) {
      return 'Height must be between ${minHeightCm.round()} and '
          '${maxHeightCm.round()} cm (about 3\'3" to 8\'2")';
    }
    return null;
  }

  static String? weightKg(double? value) {
    if (value == null) return 'Enter your weight';
    if (value < minWeightKg || value > maxWeightKg) {
      return 'Weight must be between ${minWeightKg.round()} and '
          '${maxWeightKg.round()} kg (66 to 661 lbs)';
    }
    return null;
  }

  /// The first problem with a set of body stats, or null when all are fine.
  static String? bodyStats({int? age, double? heightCm, double? weightKg}) =>
      Validators.age(age) ??
      Validators.heightCm(heightCm) ??
      Validators.weightKg(weightKg);

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