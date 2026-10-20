import 'package:flutter_test/flutter_test.dart';
import 'package:skinseries/models.dart';
import 'package:skinseries/services/api_client.dart';
import 'package:skinseries/state/app_state.dart';

import 'fake_api.dart';

/// v2.2 accounts: profile parsing, create-with-email, token fallback
/// sign-in, /api/me/account, and the recovery request helpers — all
/// against the in-memory fake (no network).
void main() {
  test('profile parses email + emailVerified; absent fields default', () {
    final full = PractitionerProfile.fromJson(const {
      'id': 'p1',
      'practiceName': 'Glow',
      'practitionerName': 'Ava',
      'accent': '#B0714F',
      'bookingLink': '',
      'email': 'ava@example.com',
      'emailVerified': true,
    });
    expect(full.email, 'ava@example.com');
    expect(full.emailVerified, isTrue);

    final legacy = PractitionerProfile.fromJson(const {
      'id': 'p2',
      'practiceName': 'Legacy',
      'practitionerName': 'Lee',
      'accent': '#B0714F',
      'bookingLink': '',
    });
    expect(legacy.email, isNull);
    expect(legacy.emailVerified, isFalse);
  });

  test('createPractice with email signs in unverified and stores token',
      () async {
    final api = FakeApi();
    final store = MemoryTokenStore();
    final state = AppState(api: api, tokenStore: store);
    final ok = await state.createPractice(
      practiceName: 'New Glow',
      practitionerName: 'Nia',
      bookingLink: '',
      accent: '#B0714F',
      email: 'nia@example.com',
      password: 'password123',
    );
    expect(ok, isTrue);
    expect(api.lastCreateEmail, 'nia@example.com');
    expect(state.profile?.email, 'nia@example.com');
    expect(state.profile?.emailVerified, isFalse);
    expect(await store.read(), 'token-created');
  });

  test('signInWithToken adopts the session for a valid token', () async {
    final api = FakeApi();
    final store = MemoryTokenStore();
    final state = AppState(api: api, tokenStore: store);
    final ok = await state.signInWithToken('  token-demo  ');
    expect(ok, isTrue);
    expect(state.isAuthenticated, isTrue);
    expect(await store.read(), 'token-demo');
  });

  test('signInWithToken rejects an empty token without calling the API',
      () async {
    final api = FakeApi();
    final state = AppState(api: api, tokenStore: MemoryTokenStore());
    final ok = await state.signInWithToken('   ');
    expect(ok, isFalse);
    expect(state.authMessage, contains('token'));
    expect(api.token, isNull);
  });

  test('addAccount sets email unverified; duplicate email surfaces 409',
      () async {
    final api = FakeApi();
    final state = AppState(api: api, tokenStore: MemoryTokenStore());
    expect(await state.signIn('demo@estiseries.app', 'GlowDemo2026'), isTrue);

    final ok = await state.addAccount('ava@example.com', 'password123');
    expect(ok, isTrue);
    expect(state.profile?.email, 'ava@example.com');
    expect(state.profile?.emailVerified, isFalse);
    expect(state.accountMessage, contains('verification'));

    final dup = await state.addAccount('taken@example.com', 'password123');
    expect(dup, isFalse);
    expect(state.accountMessage, contains('already has an account'));
  });

  test('resendVerificationEmail targets the profile email', () async {
    final api = FakeApi();
    final state = AppState(api: api, tokenStore: MemoryTokenStore());
    await state.signIn('demo@estiseries.app', 'GlowDemo2026');
    await state.addAccount('ava@example.com', 'password123');
    await state.resendVerificationEmail();
    expect(api.lastResendEmail, 'ava@example.com');
    expect(state.accountMessage, contains('sent'));
  });

  test('requestPasswordReset posts the email and returns neutral copy',
      () async {
    final api = FakeApi();
    final state = AppState(api: api, tokenStore: MemoryTokenStore());
    final message = await state.requestPasswordReset('ava@example.com');
    expect(api.lastForgotEmail, 'ava@example.com');
    expect(message, contains('reset link is on its way'));
  });
}
