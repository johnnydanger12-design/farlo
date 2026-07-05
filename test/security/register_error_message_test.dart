import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/features/auth/screens/register_screen.dart';

// security.md §4 Consolidated Risk Register, Medium — "Account enumeration:
// signup explicitly reveals 'email already exists,' inconsistent with
// login/reset's silent posture." An attacker could distinguish registered
// vs. unregistered emails by the exact message the app showed.
void main() {
  test('never shows a distinguishing "already exists" message for a duplicate-email signup failure', () {
    final message = registerFriendlyError(Exception('User already registered'));
    expect(message.toLowerCase(), isNot(contains('already exists')));
    expect(message.toLowerCase(), isNot(contains('already registered')));
  });

  test('the duplicate-email case shows the exact same message as a generic signup failure', () {
    final duplicateEmailMessage = registerFriendlyError(Exception('User already registered'));
    final genericFailureMessage = registerFriendlyError(Exception('Some unrelated signup error'));
    expect(
      duplicateEmailMessage,
      equals(genericFailureMessage),
      reason: 'if these differ, the exact wording becomes a fresh enumeration oracle even without '
          'the literal phrase "already exists"',
    );
  });

  test('network and timeout errors still get distinct, actionable messages', () {
    expect(registerFriendlyError(Exception('Socket error')), contains('internet'));
    expect(registerFriendlyError(Exception('Request timeout')), contains('timed out'));
  });
}
