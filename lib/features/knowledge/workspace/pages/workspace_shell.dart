import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:langgry/features/knowledge/services/knowledge_store.dart';
import 'package:langgry/features/knowledge/workspace/widgets/global_memo_fab.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    required this.child,
    required this.store,
    super.key,
  });

  final Widget child;
  final KnowledgeStore store;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  final _memoSelectionMode = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _memoSelectionMode.dispose();
    super.dispose();
  }

  static const _paths = [
    '/home',
    '/chat',
    '/file-import',
    '/knowledge-list',
    '/market',
    '/profile'
  ];

  int _index(String location) {
    if (location.startsWith('/file-import')) return 2;
    if (location.startsWith('/knowledge-list')) return 3;
    if (location.startsWith('/market')) return 4;
    if (location.startsWith('/profile')) return 5;
    if (location.startsWith('/chat')) return 1;
    return 0;
  }

  void _select(BuildContext context, int index) {
    if (index == 0 ||
        index == 1 ||
        index == 2 ||
        index == 3 ||
        index == 4 ||
        index == 5) {
      context.go(_paths[index]);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이 기능을 준비하고 있어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return Scaffold(
      body: SelectionModeScope(
        notifier: _memoSelectionMode,
        child: widget.child,
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _memoSelectionMode,
        builder: (context, selectionMode, child) =>
            location.startsWith('/knowledge-list') && selectionMode
                ? const SizedBox.shrink()
                : child!,
        child: GlobalMemoFab(store: widget.store),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index(location),
        onDestinationSelected: (index) => _select(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: '채팅',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: '파일',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_alt_outlined),
            label: '메모',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: '마켓',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: '마이페이지',
          ),
        ],
      ),
    );
  }
}

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
