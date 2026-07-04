import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:farlo/features/auth/models/app_user.dart';
import 'package:farlo/features/auth/providers/auth_provider.dart';
import 'package:farlo/features/food_trucks/providers/food_truck_provider.dart';
import 'package:farlo/features/food_trucks/repositories/food_truck_repository.dart';
import 'package:farlo/features/map/models/food_truck.dart';

class MockFoodTruckRepository extends Mock implements FoodTruckRepository {}

// Overrides only build() to hand back a fixed truck/user directly, bypassing
// the real build()'s Supabase.instance.client realtime-channel setup (not
// injectable) — setOpenStatus/updateOrdersAccepting themselves (the methods
// actually under test, code-quality.md §2.14's #3 highest-value target) are
// inherited unmodified from the real notifier.
class _FakeOwnerTruckNotifier extends OwnerTruckNotifier {
  _FakeOwnerTruckNotifier(this._initial);
  final FoodTruck _initial;
  @override
  Future<FoodTruck?> build() async => _initial;
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._user);
  final AppUser? _user;
  @override
  Future<AppUser?> build() async => _user;
}

FoodTruck _truck({required bool isOpen, bool ordersAccepting = true}) => FoodTruck(
      id: 't1',
      ownerId: 'owner1',
      name: 'Test Truck',
      cuisineType: 'Tacos',
      averageRating: 0,
      reviewCount: 0,
      isOpen: isOpen,
      isActive: true,
      ordersAccepting: ordersAccepting,
    );

AppUser _owner() => AppUser(
      id: 'owner1',
      email: 'owner@example.com',
      displayName: 'Owner',
      role: UserRole.owner,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockFoodTruckRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockFoodTruckRepository();
    registerFallbackValue(_truck(isOpen: false));
  });

  Future<ProviderContainer> buildContainer(FoodTruck initialTruck) async {
    final c = ProviderContainer(overrides: [
      foodTruckRepositoryProvider.overrideWithValue(mockRepo),
      authProvider.overrideWith(() => _FakeAuthNotifier(_owner())),
      ownerTruckProvider.overrideWith(() => _FakeOwnerTruckNotifier(initialTruck)),
    ]);
    // Settle both fake notifiers' build() futures before returning — setOpenStatus
    // reads authProvider synchronously via ref.read, so it must already be
    // resolved to AsyncData, not still AsyncLoading.
    await c.read(authProvider.future);
    await c.read(ownerTruckProvider.future);
    return c;
  }

  tearDown(() => container.dispose());

  group('setOpenStatus', () {
    test('optimistically updates state, then keeps it on success', () async {
      final truck = _truck(isOpen: false);
      container = await buildContainer(truck);

      when(() => mockRepo.updateOpenStatus(any(), isOpen: any(named: 'isOpen'), userId: any(named: 'userId')))
          .thenAnswer((_) async {});

      await container.read(ownerTruckProvider.notifier).setOpenStatus(true);

      final state = container.read(ownerTruckProvider).asData?.value;
      expect(state?.isOpen, isTrue);
      expect(state?.openedByUserId, 'owner1');
      expect(state?.sessionStartedAt, isNotNull);
    });

    test('rolls back to the prior truck state if the write fails, and rethrows', () async {
      final truck = _truck(isOpen: false);
      container = await buildContainer(truck);

      when(() => mockRepo.updateOpenStatus(any(), isOpen: any(named: 'isOpen'), userId: any(named: 'userId')))
          .thenThrow(Exception('network error'));

      await expectLater(
        container.read(ownerTruckProvider.notifier).setOpenStatus(true),
        throwsA(isA<Exception>()),
      );

      // The optimistic write must not survive a failed persist — this is the
      // exact rollback behavior code-quality.md flagged as untested.
      final state = container.read(ownerTruckProvider).asData?.value;
      expect(state?.isOpen, isFalse);
      expect(state?.openedByUserId, isNull);
    });
  });

  group('updateOrdersAccepting', () {
    test('optimistically updates state, then keeps it on success', () async {
      final truck = _truck(isOpen: true, ordersAccepting: true);
      container = await buildContainer(truck);

      when(() => mockRepo.updateOrdersAccepting(any(), any())).thenAnswer((_) async {});

      await container.read(ownerTruckProvider.notifier).updateOrdersAccepting(false);

      final state = container.read(ownerTruckProvider).asData?.value;
      expect(state?.ordersAccepting, isFalse);
    });

    test('rolls back to the prior value if the write fails, and rethrows', () async {
      final truck = _truck(isOpen: true, ordersAccepting: true);
      container = await buildContainer(truck);

      when(() => mockRepo.updateOrdersAccepting(any(), any())).thenThrow(Exception('network error'));

      await expectLater(
        container.read(ownerTruckProvider.notifier).updateOrdersAccepting(false),
        throwsA(isA<Exception>()),
      );

      final state = container.read(ownerTruckProvider).asData?.value;
      expect(state?.ordersAccepting, isTrue);
    });
  });
}
