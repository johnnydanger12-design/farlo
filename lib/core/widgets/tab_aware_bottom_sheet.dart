import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tab_reselect_provider.dart';

// A drop-in replacement for `showModalBottomSheet` that also closes itself
// when the user re-taps the bottom-nav tab it was opened from. Plain
// `showModalBottomSheet` (default `useRootNavigator: false`) pushes an
// imperative route onto whichever Navigator is nearest — for any screen
// inside a StatefulShellRoute branch, that's the branch's own Navigator. But
// GoRouter's `goBranch(initialLocation: true)` (what actually runs the
// existing pop-to-root behavior) only resets that Navigator's *declarative*
// GoRoute page stack — it has no way to know about, or remove, an
// imperatively-pushed sheet route sitting on top of it. Without this
// wrapper, tapping the tab while a sheet is open does nothing to the sheet.
//
// `tabIndex` must be the bottom-nav index of whichever tab this sheet is
// reachable from (0-3, same numbering in both the consumer and owner
// shells) — pass the index of the screen the sheet was opened *from*, not
// necessarily the screen's own route.
Future<T?> showTabAwareModalBottomSheet<T>({
  required BuildContext context,
  required int tabIndex,
  required WidgetBuilder builder,
  Color backgroundColor = Colors.transparent,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    shape: shape,
    builder: (sheetContext) => _TabAwareSheetDismisser(
      tabIndex: tabIndex,
      child: builder(sheetContext),
    ),
  );
}

class _TabAwareSheetDismisser extends ConsumerWidget {
  const _TabAwareSheetDismisser({required this.tabIndex, required this.child});
  final int tabIndex;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TabReselectEvent?>(tabReselectProvider, (prev, next) {
      if (next != null && next.index == tabIndex && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return child;
  }
}
