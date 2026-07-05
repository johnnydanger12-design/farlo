import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:farlo/features/orders/models/order.dart';
import 'package:farlo/features/orders/models/order_item.dart';
import 'package:farlo/features/orders/repositories/orders_data_source.dart';
import 'package:farlo/features/orders/repositories/orders_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockOrdersDataSource extends Mock implements OrdersDataSource {}

Order _order({String id = 'order1', String paymentIntentId = 'pi_1'}) => Order(
      id: id,
      truckId: 't1',
      consumerId: 'c1',
      status: 'pending',
      totalPrice: 12.5,
      paymentIntentId: paymentIntentId,
      paymentStatus: 'unpaid',
      items: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockOrdersDataSource mockDataSource;
  late OrdersRepository repository;

  const items = [
    CartItem(menuItemId: 'm1', name: 'Taco', price: 4.5, quantity: 2),
  ];

  setUp(() {
    mockDataSource = MockOrdersDataSource();
    repository = OrdersRepository(MockSupabaseClient(), dataSource: mockDataSource);
  });

  group('placeOrder', () {
    // bugs.md Executive Summary #3: a network-blip retry after a successful
    // Stripe charge must not insert a second order for the same payment
    // intent — this is the exact idempotency behavior code-quality.md §2.14's
    // 4th ARCH-2 test target flagged as untested (blocked until ARCH-1
    // introduced OrdersDataSource as a mockable seam).
    test('returns the existing order without inserting, if one already exists for this paymentIntentId', () async {
      final existing = _order();
      when(() => mockDataSource.findOrderByPaymentIntent('pi_1')).thenAnswer((_) async => existing);

      final result = await repository.placeOrder(
        truckId: 't1',
        consumerId: 'c1',
        items: items,
        paymentIntentId: 'pi_1',
      );

      expect(result, same(existing));
      verifyNever(() => mockDataSource.insertOrder(
            truckId: any(named: 'truckId'),
            consumerId: any(named: 'consumerId'),
            items: any(named: 'items'),
            paymentIntentId: any(named: 'paymentIntentId'),
            pickupNote: any(named: 'pickupNote'),
          ));
    });

    test('inserts a new order when none exists yet for this paymentIntentId', () async {
      final inserted = _order(id: 'order2');
      when(() => mockDataSource.findOrderByPaymentIntent('pi_2')).thenAnswer((_) async => null);
      when(() => mockDataSource.insertOrder(
            truckId: any(named: 'truckId'),
            consumerId: any(named: 'consumerId'),
            items: any(named: 'items'),
            paymentIntentId: any(named: 'paymentIntentId'),
            pickupNote: any(named: 'pickupNote'),
          )).thenAnswer((_) async => inserted);

      final result = await repository.placeOrder(
        truckId: 't1',
        consumerId: 'c1',
        items: items,
        pickupNote: 'Ring the bell',
        paymentIntentId: 'pi_2',
      );

      expect(result, same(inserted));
      verify(() => mockDataSource.insertOrder(
            truckId: 't1',
            consumerId: 'c1',
            items: items,
            paymentIntentId: 'pi_2',
            pickupNote: 'Ring the bell',
          )).called(1);
    });
  });
}
