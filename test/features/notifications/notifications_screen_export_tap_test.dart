import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/features/account/providers/data_export_provider.dart';
import 'package:farlo/features/auth/models/app_user.dart';
import 'package:farlo/features/auth/providers/auth_provider.dart';
import 'package:farlo/features/notifications/models/app_notification.dart';
import 'package:farlo/features/notifications/providers/notifications_provider.dart';
import 'package:farlo/features/notifications/screens/notifications_screen.dart';

// Founder-reported bug: tapping the "Your data export is ready" in-app
// notification did nothing — NotificationsScreen._handleTap's switch had no
// case for 'data_export_ready', so it silently fell through to `default:
// break`. Users had no in-app path to their export at all, only the emailed
// link. Fixed by adding a case that opens the same DataExportSheet used from
// Account > Privacy > Download My Data.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'user-1',
        email: 'test@farlo.app',
        displayName: 'Test User',
        role: UserRole.consumer,
        createdAt: DateTime(2026, 1, 1),
      );
}

void main() {
  testWidgets('tapping a data_export_ready notification opens the DataExportSheet', (tester) async {
    final notification = AppNotification(
      id: 'notif-1',
      type: 'data_export_ready',
      title: 'Your data export is ready',
      body: 'Tap to download a copy of your Farlo data. This link expires in 7 days.',
      read: true, // avoid exercising markRead(), which needs a real Supabase client
      createdAt: DateTime(2026, 7, 5),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref) => Stream.value([notification])),
          authProvider.overrideWith(_FakeAuthNotifier.new),
          // autoDispose StreamProvider — DataExportSheet reads this once opened.
          // Overridden so it never touches the uninitialized Supabase client.
          latestDataExportRequestProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Your data export is ready'), findsOneWidget);
    expect(find.text('Download Your Data'), findsNothing);

    await tester.tap(find.text('Your data export is ready'));
    await tester.pumpAndSettle();

    expect(find.text('Download Your Data'), findsOneWidget);
  });
}
