import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:farlo/features/auth/providers/auth_provider.dart';
import 'package:farlo/features/auth/repositories/auth_repository.dart';
import 'package:farlo/features/bookings/providers/bookings_provider.dart';
import 'package:farlo/features/employees/models/truck_employee.dart';
import 'package:farlo/features/employees/providers/employees_provider.dart';
import 'package:farlo/features/employees/repositories/employees_repository.dart';
import 'package:farlo/features/favorites/providers/favorites_provider.dart';
import 'package:farlo/features/food_trucks/providers/food_truck_provider.dart';
import 'package:farlo/features/map/models/food_truck.dart';

// security.md Abuse Scenario #7 — "shared-device stale-data leak": a truck's
// employee/owner hands their phone to a second, different employee/owner
// without the app being closed. `.autoDispose` alone does not clear a
// provider on sign-out — it only tears down once its last widget listener
// unmounts — so without an explicit invalidation, the second user could
// briefly see the first user's cached counts/lists/badges. AuthNotifier.signOut()
// now explicitly invalidates every provider that caches per-user/per-truck
// data (see auth_provider.dart's `_invalidateUserScopedProviders`).
//
// The `.family` providers below (`truckEmployeesProvider`,
// `pendingBookingCountProvider`) are the genuine risk case: they're keyed by
// truck/entity id, not by auth user, and have no other mechanism that would
// clear them on sign-out — the explicit invalidate call is the only thing
// standing between them and stale data if a key were ever reused across
// users. `favoritesListProvider` and `ownerTruckProvider` already `ref.watch`
// the auth provider internally and would self-heal even without this fix;
// they're included to confirm the full sign-out-then-sign-in-as-someone-else
// path still ends up correct end-to-end, not to isolate this fix's own causal
// contribution for those two.
class MockAuthRepository extends Mock implements AuthRepository {}

class MockEmployeesRepository extends Mock implements EmployeesRepository {}

// Overrides only build() to hand back a fixed truck directly, bypassing the
// real build()'s Supabase.instance.client realtime-channel setup (not
// injectable in a unit test) — same pattern as food_truck_provider_test.dart's
// _FakeOwnerTruckNotifier. Must subclass the concrete OwnerTruckNotifier
// itself, not just implement AsyncNotifier<FoodTruck?> — overrideWith requires
// the exact notifier type the provider was declared with.
class _FakeOwnerTruckNotifier extends OwnerTruckNotifier {
  _FakeOwnerTruckNotifier(this._onBuild);
  final FoodTruck? Function() _onBuild;
  @override
  Future<FoodTruck?> build() async => _onBuild();
}

void main() {
  late MockAuthRepository mockAuthRepo;
  late MockEmployeesRepository mockEmployeesRepo;
  late ProviderContainer container;
  late int pendingBookingBuildCount;
  late int favoritesBuildCount;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    when(() => mockAuthRepo.fetchCurrentUser()).thenAnswer((_) async => null);
    when(() => mockAuthRepo.signOut()).thenAnswer((_) async {});

    mockEmployeesRepo = MockEmployeesRepository();
    when(() => mockEmployeesRepo.fetchEmployees(any())).thenAnswer((_) async => <TruckEmployee>[]);

    pendingBookingBuildCount = 0;
    favoritesBuildCount = 0;

    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(mockAuthRepo),
      // .family AsyncNotifierProvider
      employeesRepositoryProvider.overrideWithValue(mockEmployeesRepo),
      // .family StreamProvider
      pendingBookingCountProvider.overrideWith((ref, truckId) {
        pendingBookingBuildCount++;
        return Stream.value(pendingBookingBuildCount);
      }),
      // plain FutureProvider
      favoritesListProvider.overrideWith((ref) {
        favoritesBuildCount++;
        return Future.value(const []);
      }),
    ]);
  });

  tearDown(() => container.dispose());

  test('signOut() invalidates ownerTruckProvider (plain AsyncNotifierProvider)', () async {
    var ownerTruckBuildCount = 0;
    final localContainer = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(mockAuthRepo),
      ownerTruckProvider.overrideWith(() => _FakeOwnerTruckNotifier(() {
            ownerTruckBuildCount++;
            return null;
          })),
    ]);
    addTearDown(localContainer.dispose);

    await localContainer.read(authProvider.future);
    await localContainer.read(ownerTruckProvider.future);
    expect(ownerTruckBuildCount, 1);

    await localContainer.read(authProvider.notifier).signOut();
    // Re-reading after invalidation must trigger a fresh build, not return
    // the previous owner's cached state.
    await localContainer.read(ownerTruckProvider.future);
    expect(ownerTruckBuildCount, 2);
  });

  test('signOut() invalidates truckEmployeesProvider (.family AsyncNotifierProvider)', () async {
    await container.read(authProvider.future);
    await container.read(truckEmployeesProvider('truck-1').future);
    verify(() => mockEmployeesRepo.fetchEmployees('truck-1')).called(1);

    await container.read(authProvider.notifier).signOut();
    await container.read(truckEmployeesProvider('truck-1').future);
    verify(() => mockEmployeesRepo.fetchEmployees('truck-1')).called(1);
  });

  test('signOut() invalidates pendingBookingCountProvider (.family StreamProvider)', () async {
    await container.read(authProvider.future);
    container.listen(pendingBookingCountProvider('truck-1'), (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(pendingBookingBuildCount, 1);

    await container.read(authProvider.notifier).signOut();
    container.listen(pendingBookingCountProvider('truck-1'), (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(pendingBookingBuildCount, 2);
  });

  test('signOut() invalidates favoritesListProvider (plain FutureProvider)', () async {
    await container.read(authProvider.future);
    await container.read(favoritesListProvider.future);
    expect(favoritesBuildCount, 1);

    await container.read(authProvider.notifier).signOut();
    await container.read(favoritesListProvider.future);
    expect(favoritesBuildCount, 2);
  });
}
