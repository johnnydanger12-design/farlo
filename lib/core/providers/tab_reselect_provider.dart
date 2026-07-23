import 'package:flutter_riverpod/flutter_riverpod.dart';

// Bumped whenever the user taps the bottom-nav tab they're already on.
// GoRouter's own `goBranch(initialLocation: true)` already pops that branch
// back to its root screen if a sub-page was pushed on top — this event is
// for the other half: a root screen that's already the visible top of its
// branch (nothing to pop) listens for its own index and treats the tap as a
// refresh signal instead. `tick` guarantees a new value even if the same
// index is tapped twice in a row, since StateProvider only notifies on an
// actual value change.
class TabReselectEvent {
  const TabReselectEvent(this.index, this.tick);
  final int index;
  final int tick;
}

class TabReselectNotifier extends Notifier<TabReselectEvent?> {
  @override
  TabReselectEvent? build() => null;

  void fire(int index) => state = TabReselectEvent(index, DateTime.now().microsecondsSinceEpoch);
}

final tabReselectProvider = NotifierProvider<TabReselectNotifier, TabReselectEvent?>(
  TabReselectNotifier.new,
);
