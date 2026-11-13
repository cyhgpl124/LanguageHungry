import 'package:flutter/material.dart';

class SelectionModeScope extends InheritedNotifier<ValueNotifier<bool>> {
  const SelectionModeScope({
    required super.notifier,
    required super.child,
    super.key,
  });

  static void update(BuildContext context, bool selectionMode) {
    final notifier =
        context.getInheritedWidgetOfExactType<SelectionModeScope>()?.notifier;
    if (notifier != null && notifier.value != selectionMode) {
      notifier.value = selectionMode;
    }
  }
}
