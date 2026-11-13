import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/webview/global_webview_dock.dart';
import 'package:go_router/go_router.dart';

import 'package:langgry/core/localization/app_strings.dart';
import 'package:langgry/features/knowledge/services/knowledge_store.dart';
import 'package:langgry/features/knowledge/workspace/widgets/global_memo_fab.dart';
import 'package:langgry/features/knowledge/workspace/widgets/selection_mode_scope.dart';

export 'package:langgry/features/knowledge/workspace/widgets/selection_mode_scope.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    required this.child,
    required this.store,
    this.showWebViewDock,
    super.key,
  });

  final Widget child;
  final KnowledgeStore store;
  final bool? showWebViewDock;

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
      const SnackBar(content: AppText('이 기능을 준비하고 있어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final strings = AppStrings.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SelectionModeScope(
            notifier: _memoSelectionMode,
            child: widget.child,
          ),
          Positioned.fill(
            child: SafeArea(
              child: ValueListenableBuilder<bool>(
                valueListenable: _memoSelectionMode,
                builder: (context, selectionMode, child) =>
                    location.startsWith('/knowledge-list') && selectionMode
                        ? const SizedBox.shrink()
                        : child!,
                child: GlobalMemoFab(store: widget.store),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showWebViewDock ?? !kIsWeb) const GlobalWebViewDock(),
          NavigationBar(
            selectedIndex: _index(location),
            onDestinationSelected: (index) => _select(context, index),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: strings.home,
              ),
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: strings.chat,
              ),
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                label: strings.files,
              ),
              NavigationDestination(
                icon: const Icon(Icons.note_alt_outlined),
                label: strings.notes,
              ),
              NavigationDestination(
                icon: const Icon(Icons.storefront_outlined),
                selectedIcon: const Icon(Icons.storefront_rounded),
                label: strings.market,
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                label: strings.myPage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
