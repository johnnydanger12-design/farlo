import 'dart:async';

/// Applied to every repository network call — without this, a hung Supabase
/// request (bad cell signal, server hiccup) blocked the UI indefinitely with
/// a spinner that never resolved; there was no `.timeout()` anywhere in the
/// networking layer (performance.md §3, Top 5 finding #1). Generalizes the
/// pattern already used locally in auth_provider.dart's `_authTimeout`.
const networkTimeout = Duration(seconds: 15);

extension NetworkTimeout<T> on Future<T> {
  Future<T> get withNetworkTimeout => timeout(
        networkTimeout,
        onTimeout: () => throw TimeoutException(
          'Request timed out. Check your connection and try again.',
        ),
      );
}
