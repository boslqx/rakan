import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/settings/screens/change_password_dialog.dart';

/// V-03: Change Password must enforce the same rules as sign-up.
void main() {
  String? check(String newPassword, {String? confirm, String current = 'Old!Pass1'}) =>
      ChangePasswordDialog.validate(
        current: current,
        newPassword: newPassword,
        confirm: confirm ?? newPassword,
      );

  test('rejects passwords that sign-up would reject', () {
    expect(check('abcdef'), 'New password does not meet all requirements');
    expect(check('rakan123'), 'New password does not meet all requirements');
    expect(check('Rakan123'), 'New password does not meet all requirements');
  });

  test('accepts a password that meets every sign-up requirement', () {
    expect(check('Rakan12!'), isNull);
  });

  test('still requires every field and a matching confirmation', () {
    expect(check('Rakan12!', current: ''), 'All fields are required');
    expect(check('Rakan12!', confirm: 'Rakan12?'), 'Passwords do not match');
  });
}
