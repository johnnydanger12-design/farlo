import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:farlo/features/auth/models/app_user.dart';
import 'package:farlo/features/auth/providers/auth_provider.dart';
import 'package:farlo/features/auth/repositories/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

AppUser _user() => AppUser(
      id: 'u1',
      email: 'test@example.com',
      displayName: 'Test User',
      role: UserRole.consumer,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  // AuthNotifier.build() returns null (unauthenticated) in every test here so
  // it never reaches _subscribeToProfileChanges, which touches the real
  // Supabase.instance.client singleton directly (not injectable) — that path
  // is out of scope for a pure unit test without a live/fake Supabase
  // instance, so these tests target signInWithEmail's own logic instead,
  // which is code-quality.md §2.14's actual point: "currently has zero
  // coverage of its timeout/rollback logic."
  late MockAuthRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockAuthRepository();
    when(() => mockRepo.fetchCurrentUser()).thenAnswer((_) async => null);
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
    );
  });

  tearDown(() => container.dispose());

  test('build() resolves to AsyncData(null) when no session exists', () async {
    final result = await container.read(authProvider.future);
    expect(result, isNull);
    expect(container.read(authProvider), isA<AsyncData<AppUser?>>());
  });

  test('signInWithEmail success updates state to AsyncData(user)', () async {
    await container.read(authProvider.future); // settle initial build

    when(() => mockRepo.signInWithEmail(any(), any()))
        .thenAnswer((_) async => _user());

    await container.read(authProvider.notifier).signInWithEmail('test@example.com', 'password123');

    final state = container.read(authProvider);
    expect(state, isA<AsyncData<AppUser?>>());
    expect(state.asData?.value?.id, 'u1');
  });

  test('signInWithEmail failure updates state to AsyncError, not a silent no-op', () async {
    await container.read(authProvider.future);

    when(() => mockRepo.signInWithEmail(any(), any()))
        .thenThrow(const AuthApiExceptionStub('Invalid login credentials'));

    await container.read(authProvider.notifier).signInWithEmail('test@example.com', 'wrong');

    final state = container.read(authProvider);
    expect(state.hasError, isTrue);
  });

  test('signInWithEmail times out after 20s if the repository call never completes', () {
    fakeAsync((async) {
      // Fresh container inside fakeAsync so its Zone/Timer usage lines up
      // with FakeAsync's virtual clock.
      final repo = MockAuthRepository();
      when(() => repo.fetchCurrentUser()).thenAnswer((_) async => null);
      final c = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);

      // Settle the initial build.
      c.read(authProvider.notifier);
      async.flushMicrotasks();

      // Simulates a hung network call — signInWithEmail's own timeout
      // wrapper (_authTimeout = 20s) must fire instead of hanging forever.
      when(() => repo.signInWithEmail(any(), any()))
          .thenAnswer((_) => Completer<AppUser>().future);

      c.read(authProvider.notifier).signInWithEmail('test@example.com', 'password123');
      async.elapse(const Duration(seconds: 21));

      final state = c.read(authProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<TimeoutException>());
    });
  });
}

/// Minimal stand-in so this test doesn't need to depend on gotrue's exact
/// exception constructor shape — AuthNotifier only cares that *something*
/// was thrown, not its concrete type.
class AuthApiExceptionStub implements Exception {
  const AuthApiExceptionStub(this.message);
  final String message;
  @override
  String toString() => message;
}
