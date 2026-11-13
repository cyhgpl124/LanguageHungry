import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/localization/app_text_catalog.dart';
import 'package:langgry/core/localization/language_display.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'package:langgry/core/webview/global_webview_dock.dart';
import 'package:langgry/features/profile/permissions/pages/permission_settings_screen.dart';
import 'package:langgry/features/auth/splash/pages/splash_screen.dart';
import 'package:langgry/features/knowledge/services/memory_knowledge_store.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/files/pages/file_parsing_screen.dart';
import 'package:langgry/features/knowledge/list/pages/dynamic_list_screen.dart';
import 'package:langgry/features/knowledge/memos/pages/memo_canvas_workspace_screen.dart';
import 'package:langgry/features/knowledge/memos/services/memo_canvas_service.dart';
import 'package:langgry/features/knowledge/memos/services/memo_mode_assistant.dart';
import 'package:langgry/features/knowledge/memos/pages/memo_workspace_screen.dart';
import 'package:langgry/features/knowledge/workspace/pages/workspace_shell.dart';
import 'package:langgry/features/knowledge/workspace/widgets/global_memo_fab.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';

void main() {
  test('provides every supported translation for catalog entries', () {
    const locales = {'ko', 'en', 'ja', 'zh', 'es', 'fr', 'de'};
    for (final translations in AppTextCatalog.translations.values) {
      expect(translations.keys.toSet(), locales);
    }
    for (final translations in AppTextCatalog.templates.values) {
      expect(translations.keys.toSet(), locales);
    }
  });

  test('maps native-language names to supported locale codes', () {
    expect(LanguageDisplay.localeCodeForStorageName('영어'), 'en');
    expect(LanguageDisplay.localeCodeForStorageName('일본어'), 'ja');
    expect(LanguageDisplay.localeCodeForStorageName('알 수 없는 언어'), 'ko');
    expect(
        LanguageDisplay.fromStorageName('영어').localizedName('en'), 'English');
    expect(LanguageDisplay.fromStorageName('영어').localizedName('ja'), '英語');
  });

  test('permission matrix defaults every role and feature to allowed', () {
    final matrix = PermissionMatrix.allEnabled();
    for (final feature in PermissionFeatures.all) {
      for (final tier in PermissionTier.values) {
        expect(matrix.allows(feature.key, tier), isTrue);
      }
    }

    final restricted = matrix.withGrant(
        PermissionFeatures.chat.key, PermissionTier.free, false);
    expect(
      restricted.allows(PermissionFeatures.chat.key, PermissionTier.free),
      isFalse,
    );
    expect(
      restricted.allows(PermissionFeatures.chat.key, PermissionTier.pro),
      isTrue,
    );
    expect(
      PermissionMatrix.fromMap(restricted.toMap())
          .allows(PermissionFeatures.chat.key, PermissionTier.free),
      isFalse,
    );
  });

  testWidgets('denied features show the upgrade screen', (tester) async {
    final permissions = _MemoryPermissionRepository(
      matrix: PermissionMatrix.allEnabled().withGrant(
        PermissionFeatures.home.key,
        PermissionTier.free,
        false,
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: permissions,
        child: const MaterialApp(
          locale: Locale('en'),
          home: PermissionGate(
            feature: PermissionFeatures.home,
            child: Text('Allowed page'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This feature isn\'t available with your current access.'),
        findsOneWidget);
    expect(find.text('Allowed page'), findsNothing);
  });

  testWidgets('memo FAB drag position persists between widget launches',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = MemoryKnowledgeStore();
    final permissions =
        _MemoryPermissionRepository(matrix: PermissionMatrix.allEnabled());
    final fab = RepositoryProvider<PermissionPolicyRepository>.value(
      value: permissions,
      child: MaterialApp(
        home: Scaffold(body: GlobalMemoFab(store: store)),
      ),
    );

    await tester.pumpWidget(fab);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('global-memo-fab-position')),
      const Offset(-80, -100),
    );
    await tester.pumpAndSettle();
    final movedPosition = tester
        .getTopLeft(find.byKey(const ValueKey('global-memo-fab-position')));
    final savedX = preferences.getDouble('globalMemoFab.positionX');
    final savedY = preferences.getDouble('globalMemoFab.positionY');
    expect(savedX, lessThan(1));
    expect(savedY, lessThan(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(fab);
    await tester.pumpAndSettle();
    final restoredPosition = tester
        .getTopLeft(find.byKey(const ValueKey('global-memo-fab-position')));
    expect(restoredPosition, movedPosition);

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('memo FAB opens unified memo dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryKnowledgeStore();
    final permissions =
        _MemoryPermissionRepository(matrix: PermissionMatrix.allEnabled());
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: permissions,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: GlobalMemoFab(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('global-memo-fab-button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('unified-memo-title')),
      'Quick memo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('unified-memo-content')),
      'A plain note',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final memo = (await store.listNodes()).single;
    expect(memo.title, 'Quick memo');
    expect(memo.content, 'A plain note');

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('permission settings remain restricted to the superuser',
      (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
          superuser: false,
        ),
        child: const MaterialApp(
          locale: Locale('en'),
          home: PermissionGate(
            feature: PermissionFeatures.permissionSettings,
            superuserOnly: true,
            child: Text('Permission administration'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Permission administration'), findsNothing);
    expect(find.text('Permission settings'), findsOneWidget);
  });

  testWidgets('permission settings UI uses localized AppText copy',
      (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
          superuser: true,
          usingDefaultMatrix: true,
        ),
        child: const MaterialApp(
          locale: Locale('en'),
          home: PermissionSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Permission settings'), findsNWidgets(2));
    expect(find.text('Screen / feature'), findsOneWidget);
    expect(
      find.text(
        'Showing the default permission matrix. Deploy the latest Firestore rules to save changes.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('global webview opens, resizes, snaps and hides in two drags',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
        ),
        child: const MaterialApp(
          locale: Locale('en'),
          home: Scaffold(body: GlobalWebViewDock()),
        ),
      ),
    );
    expect(find.text('Open web view'), findsNothing);
    expect(find.text('Global web view'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('webview-hidden-handle'))).height,
      10,
    );

    await tester.drag(
        find.byKey(const Key('webview-hidden-handle')), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webview-panel')), findsOneWidget);
    final minimumHeight =
        tester.getSize(find.byKey(const Key('webview-panel'))).height;
    expect(minimumHeight, greaterThanOrEqualTo(260));

    await tester.drag(
      find.byKey(const Key('webview-drag-handle')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('webview-panel'))).height,
      greaterThan(minimumHeight),
    );

    await tester.drag(
      find.byKey(const Key('webview-drag-handle')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('webview-panel'))).height,
      minimumHeight,
    );

    await tester.drag(
      find.byKey(const Key('webview-drag-handle')),
      const Offset(0, 50),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webview-panel')), findsNothing);
    expect(find.text('Open web view'), findsNothing);
  });

  testWidgets('webview permission denial directs the user to upgrade',
      (tester) async {
    final permissions = _MemoryPermissionRepository(
      matrix: PermissionMatrix.allEnabled().withGrant(
        PermissionFeatures.webView.key,
        PermissionTier.free,
        false,
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: permissions,
        child: const MaterialApp(
          locale: Locale('en'),
          home: Scaffold(body: GlobalWebViewDock()),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('webview-hidden-handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webview-panel')), findsNothing);
    expect(
      find.text('This feature isn\'t available with your current access.'),
      findsOneWidget,
    );
  });

  testWidgets('webview permission prompt works inside the routed app shell',
      (tester) async {
    final store = MemoryKnowledgeStore();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              WorkspaceShell(store: store, child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const Scaffold(body: Text('Home route')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled().withGrant(
            PermissionFeatures.webView.key,
            PermissionTier.free,
            false,
          ),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final dockTop =
        tester.getTopLeft(find.byKey(const Key('webview-hidden-handle'))).dy;
    final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    expect(dockTop, lessThan(navigationTop));
    await tester.tap(find.byKey(const Key('webview-hidden-handle')));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace shell can hide the webview dock for web builds',
      (tester) async {
    final store = MemoryKnowledgeStore();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => WorkspaceShell(
            store: store,
            showWebViewDock: false,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const Scaffold(body: Text('Home route')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webview-hidden-handle')), findsNothing);
    expect(find.byKey(const Key('webview-panel')), findsNothing);
  });

  testWidgets('localizes app copy and leaves unregistered text unchanged',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              AppText('마이페이지'),
              AppText('친구목록'),
              AppText('가입 이메일은 user@example.com 입니다.'),
              AppText('사용자가 작성한 메모'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('My Page'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(
      find.text('The registered email address is user@example.com.'),
      findsOneWidget,
    );
    expect(find.text('사용자가 작성한 메모'), findsOneWidget);
  });

  test('persists chat autosave preferences and progress', () {
    final settings = ChatSettings.fromMap(
      ChatSettings(
        name: 'Assistant',
        partnerType: 'AI',
        role: 'Helper',
        tone: 'Friendly',
        saveEvery: -1,
        selectedSources: const [],
        autoSaveCategory: 'Study',
        autoSaveInstruction: 'Organize key points.',
        autoSaveThrough: 18,
        conversationSummary: 'The user is learning English for travel.',
        conversationSummaryThroughMessageId: 'message-18',
      ).toMap(),
    );

    expect(settings.saveEvery, -1);
    expect(settings.autoSaveCategory, 'Study');
    expect(settings.autoSaveInstruction, 'Organize key points.');
    expect(settings.autoSaveThrough, 18);
    expect(
      settings.conversationSummary,
      'The user is learning English for travel.',
    );
    expect(settings.conversationSummaryThroughMessageId, 'message-18');
  });

  testWidgets('shows the LANGGRY splash brand', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(onFinished: () {}),
      ),
    );
    expect(find.text('LANGGRY'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
  });

  testWidgets(
      'adds a custom-property list entry from a popup on a short screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryKnowledgeStore();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DynamicListScreen(store: store, embedded: true),
      ),
    );
    await tester.pumpAndSettle();
    final buttonY = tester.getCenter(find.byTooltip('검색')).dy;
    expect(tester.getCenter(find.byTooltip('리스트 추가')).dy, buttonY);
    expect(tester.getCenter(find.byTooltip('엑셀/CSV 업로드')).dy, buttonY);
    expect(find.text('태그 필터'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('리스트 추가'));
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('탭'), findsNothing);
    expect(find.text('콜론 (:)'), findsOneWidget);
    await tester.tap(find.text('사용자 지정').last);
    await tester.pumpAndSettle();
    expect(find.text('기호'), findsOneWidget);
    expect(find.text('기호'), findsOneWidget);
    await tester.enterText(dialogFields.at(0), '오늘');
    await tester.enterText(dialogFields.at(1), '상태,날짜');
    await tester.enterText(
      dialogFields.at(2),
      '기억하기,오늘\n${List.generate(12, (index) => '복습$index,날짜$index').join('\n')}',
    );
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('기억하기'), findsNothing);
    await tester.tap(find.text('오늘'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('상태'), findsOneWidget);
    expect(find.text('기억하기'), findsOneWidget);
    expect(find.text('날짜'), findsOneWidget);
    expect(find.text('오늘'), findsNWidgets(3));
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('오늘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    final editFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(editFields.at(0), '수정된 제목');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('수정된 제목'), findsOneWidget);
    expect(find.text('오늘'), findsNothing);

    await tester.longPress(find.text('수정된 제목'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('수정된 제목'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('opens plot details and supports long-press edit and delete',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryKnowledgeStore();
    final now = DateTime(2025, 1, 5);
    await store.insertNode(
      KnowledgeNode(
        id: 'plot-a',
        type: 'knowledge',
        title: 'Plot A',
        content: 'First scene\nSecond scene\nFinal scene',
        createdAt: now,
        updatedAt: now,
        metadata: const {'mode': 'plot', 'display': '플롯'},
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
        ),
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MemoWorkspaceScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('플롯 모드'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plot A'));
    await tester.pumpAndSettle();
    expect(find.text('First scene\nSecond scene\nFinal scene'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Plot A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'Updated Plot',
    );
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Plot'), findsOneWidget);

    await tester.longPress(find.text('Updated Plot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Plot'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('toggles a memo in selection mode from its card',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryKnowledgeStore();
    final selectionMode = ValueNotifier<bool>(false);
    await store.insertNode(
      KnowledgeNode(
        id: 'memo-a',
        type: 'memo',
        title: 'Memo A',
        content: 'First memo',
        createdAt: DateTime(2025, 1, 5),
        updatedAt: DateTime(2025, 1, 5),
        embedding: const [1, 0],
        metadata: const {'mode': 'memo', 'language': '한국어', 'level': '2'},
      ),
    );
    await store.insertNode(
      KnowledgeNode(
        id: 'memo-b',
        type: 'memo',
        title: 'Memo B',
        content: 'Second memo',
        createdAt: DateTime(2025, 1, 4),
        updatedAt: DateTime(2025, 1, 4),
        embedding: const [0.8, 0.6],
        metadata: const {'mode': 'memo', 'language': '영어', 'level': '1'},
      ),
    );
    await store.insertNode(
      KnowledgeNode(
        id: 'memo-c',
        type: 'memo',
        title: 'Memo C',
        content: 'Third memo',
        createdAt: DateTime(2025, 1, 3),
        updatedAt: DateTime(2025, 1, 3),
        embedding: const [0.6, 0.8],
        metadata: const {'mode': 'memo', 'language': '영어', 'level': '1'},
      ),
    );

    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
        ),
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SelectionModeScope(
            notifier: selectionMode,
            child: MemoWorkspaceScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Memo A'), findsOneWidget);
    expect(find.text('유사도 80%'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('2단계 메모'), findsOneWidget);

    await tester.longPress(find.text('Memo B'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selectionMode.value, isTrue);
    await tester.tap(find.text('Memo C'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_box_rounded), findsNWidgets(2));

    await tester.tap(find.text('Memo B'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('파일 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Study');
    await tester.tap(find.text('파일 만들기'));
    await tester.pumpAndSettle();
    final file = (await store.listFiles()).single;
    expect(
      (await store.listNodes()).any((node) => node.type == 'file'),
      isFalse,
    );
    expect(file.content, contains('<style>'));
    expect(file.content, contains('font-weight:700'));
    expect(file.content, contains('<h1>Memo C</h1>'));
    expect(file.metadata['category'], 'Study');
    expect(selectionMode.value, isFalse);
    final backup = await store.exportJson();
    final restoredStore = MemoryKnowledgeStore();
    await restoredStore.importJson(backup);
    expect(
        (await restoredStore.listFiles()).single.metadata['category'], 'Study');
    await restoredStore.close();
    await store.upsertFile(
      KnowledgeNode(
        id: 'other-file',
        type: 'file',
        title: 'Other document',
        content: '<!doctype html><h1>Other topic</h1>',
        createdAt: DateTime(2025, 1, 6),
        updatedAt: DateTime(2025, 1, 6),
        metadata: const {'category': 'Other'},
      ),
    );

    await tester.pumpWidget(MaterialApp(home: FileParsingScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text(file.title), findsOneWidget);
    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(find.text('Other document'), findsOneWidget);
    expect(find.text(file.title), findsNothing);
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Memo C');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Other document'), findsNothing);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text(file.content), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    selectionMode.dispose();
    await store.close();
  });

  testWidgets('pasted HTML is AI-completed and saved', (tester) async {
    final store = MemoryKnowledgeStore();
    final permissions =
        _MemoryPermissionRepository(matrix: PermissionMatrix.allEnabled());
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: permissions,
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: FileParsingScreen(
            store: store,
            recoverHtml: (source) async {
              expect(source, contains('<h1>My page</h1>'));
              return '<!doctype html><html><body><main><h1>My page</h1>'
                  '<p>Preserved content</p></main></body></html>';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_note_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('html-paste-title')),
      'Pasted page',
    );
    await tester.enterText(
      find.byKey(const ValueKey('html-paste-content')),
      '<h1>My page</h1>',
    );
    await tester.tap(find.text('AI로 화면 구성 보완'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('html-paste-content')),
          )
          .controller!
          .text,
      contains('<main>'),
    );
    await tester.tap(find.text('파일 저장'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pasted');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    final saved = (await store.listFiles()).single;
    expect(saved.content, contains('Preserved content'));
    expect(saved.metadata['source'], 'pasted');
    expect(saved.metadata['layoutRepaired'], 'true');

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  test('memo canvas creates an outline and keeps component history', () async {
    final store = MemoryKnowledgeStore();
    final service = MemoCanvasService(store);
    final document = await service.createDocument(
      title: 'Study plan',
      content: 'Review vocabulary',
      kind: MemoDocumentKind.memo,
      options: const MemoCanvasAiOptions(),
    );

    final components = await service.loadComponents(document.id);
    expect(components, hasLength(2));
    expect(components.first.metadata['componentKind'], 'outline');
    expect(components.first.content, 'Study plan');
    expect(components.last.content, 'Review vocabulary');

    await service.addRevision(components.last, revisionType: 'beforeEdit');
    await service.saveAiHistory(
      components.last,
      response: 'Review vocabulary daily',
      request: 'Make this actionable',
    );
    expect(await service.loadHistory(components.last.id), hasLength(2));

    await service.deleteDocument(document);
    expect(await service.loadDocuments(), isEmpty);
    expect(await store.listNodes(), isEmpty);
    await store.close();
  });

  testWidgets('memo canvas creates documents with a required outline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryKnowledgeStore();
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
        ),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MemoCanvasWorkspaceScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New document'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('unified-memo-title')),
      'New document',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final documents = await MemoCanvasService(store).loadDocuments();
    expect(documents, hasLength(1));
    final components =
        await MemoCanvasService(store).loadComponents(documents.single.id);
    expect(components, hasLength(1));
    expect(components.first.metadata['componentKind'], 'outline');
    expect(
      find.byKey(ValueKey('memo-add-bottom-${components.first.id}')),
      findsOneWidget,
    );
    for (final position in ['top', 'left', 'right']) {
      expect(
        find.byKey(ValueKey('memo-add-$position-${components.first.id}')),
        findsNothing,
      );
    }

    await tester.tap(
      find.byKey(ValueKey('memo-add-bottom-${components.first.id}')),
    );
    await tester.pumpAndSettle();
    final componentDialog = find.byType(AlertDialog);
    final kindDropdown =
        find.byType(DropdownButtonFormField<AssistantDisplayMode>);
    await tester.tap(kindDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table').last);
    await tester.pumpAndSettle();
    final componentFields = find.descendant(
      of: componentDialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(componentFields.at(0), 'Daily review');
    await tester.enterText(
      componentFields.at(1),
      'Task\tStatus\nReview\tReady',
    );
    await tester.tap(
      find.descendant(
        of: componentDialog,
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();

    final updatedComponents =
        await MemoCanvasService(store).loadComponents(documents.single.id);
    final table = updatedComponents.singleWhere(
      (item) => item.title == 'Daily review',
    );
    expect(table.metadata['componentKind'], 'table');
    expect(table.content, contains('Review\tReady'));

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    final editDialog = find.byType(AlertDialog);
    final editFields = find.descendant(
      of: editDialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(editFields.at(0), 'Daily review updated');
    await tester.tap(
      find.descendant(of: editDialog, matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(
      (await MemoCanvasService(store).loadComponents(documents.single.id))
          .any((item) => item.title == 'Daily review updated'),
      isTrue,
    );
    final editedComponents =
        await MemoCanvasService(store).loadComponents(documents.single.id);
    final editedTable = editedComponents.singleWhere(
      (item) => item.title == 'Daily review updated',
    );
    await tester.tap(
      find.byKey(ValueKey('memo-add-bottom-${editedTable.id}')),
    );
    await tester.pumpAndSettle();
    final leftInsertDialog = find.byType(AlertDialog);
    final leftInsertFields = find.descendant(
      of: leftInsertDialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(leftInsertFields.at(0), 'Later insert');
    await tester.enterText(leftInsertFields.at(1), 'After the table');
    await tester.tap(
      find.descendant(
        of: leftInsertDialog,
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();
    final orderedComponents =
        await MemoCanvasService(store).loadComponents(documents.single.id);
    expect(
      orderedComponents.indexWhere((item) => item.title == 'Later insert'),
      orderedComponents.indexWhere(
            (item) => item.title == 'Daily review updated',
          ) +
          1,
    );
    final laterInsert = orderedComponents.singleWhere(
      (item) => item.title == 'Later insert',
    );
    final tableComponent = orderedComponents.singleWhere(
      (item) => item.title == 'Daily review updated',
    );
    final laterFinder = find.byKey(ValueKey('memo-reorder-${laterInsert.id}'));
    final tableFinder =
        find.byKey(ValueKey('memo-reorder-${tableComponent.id}'));
    final laterTopLeft = tester.getTopLeft(laterFinder);
    final gesture = await tester.startGesture(
      laterTopLeft + const Offset(20, 20),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final tableCenter = tester.getCenter(tableFinder);
    await gesture.moveTo(tableCenter - const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    final reorderedComponents =
        await MemoCanvasService(store).loadComponents(documents.single.id);
    expect(
      reorderedComponents.indexWhere((item) => item.title == 'Later insert'),
      lessThan(
        reorderedComponents.indexWhere(
          (item) => item.title == 'Daily review updated',
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('current memo split view includes independent search panes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryKnowledgeStore();
    final service = MemoCanvasService(store);
    final first = await service.createDocument(
      title: 'Canary',
      content: 'yellow bird',
      kind: MemoDocumentKind.memo,
      options: const MemoCanvasAiOptions(),
    );
    final second = await service.createDocument(
      title: 'Harbor',
      content: 'blue water',
      kind: MemoDocumentKind.memo,
      options: const MemoCanvasAiOptions(),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MemoCanvasWorkspaceScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Split view'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoWorkspaceScreen), findsNothing);
    expect(find.byKey(const ValueKey('memo-split-sort-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('memo-split-sort-right')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('memo-split-search-left')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('memo-split-search-right')), findsOneWidget);
    expect(
      find.byKey(ValueKey('memo-split-result-left-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('memo-split-result-right-${second.id}')),
      findsOneWidget,
    );
    expect(find.byType(GridView), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('memo-view-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const ValueKey('memo-split-search-left')),
      'Canary',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('memo-split-result-left-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('memo-split-result-left-${second.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('memo-split-result-right-${second.id}')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey('memo-split-result-right-${second.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('memo-split-back-right')), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('memo-split-document-right-${second.id}'),
      ),
      findsOneWidget,
    );
    expect(find.text('blue water'), findsOneWidget);
    expect(find.text('Harbor'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('memo-split-back-right')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('memo-split-search-right')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('memo-split-search-left')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });

  testWidgets('memo FAB opens unified memo dialog with mode selection inside popup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryKnowledgeStore();
    await tester.pumpWidget(
      RepositoryProvider<PermissionPolicyRepository>.value(
        value: _MemoryPermissionRepository(
          matrix: PermissionMatrix.allEnabled(),
        ),
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: GlobalMemoFab(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('global-memo-fab-button')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('unified-memo-title')),
      'Weekly graph',
    );
    await tester.enterText(
      find.byKey(const ValueKey('unified-memo-content')),
      '4, 7, 5, 9',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final nodes = await store.listNodes();
    expect(nodes, hasLength(1));
    expect(nodes.single.title, 'Weekly graph');
    expect(nodes.single.content, '4, 7, 5, 9');

    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });
}

class _MemoryPermissionRepository implements PermissionPolicyRepository {
  _MemoryPermissionRepository({
    required this.matrix,
    this.superuser = false,
    this.usingDefaultMatrix = false,
  });

  PermissionMatrix matrix;
  final bool superuser;
  final bool usingDefaultMatrix;

  @override
  bool get isSuperuser => superuser;

  @override
  bool get isUsingDefaultMatrix => usingDefaultMatrix;

  @override
  Future<PermissionTier> currentTier() async => PermissionTier.free;

  @override
  Future<PermissionMatrix> loadMatrix() async => matrix;

  @override
  Future<void> saveMatrix(PermissionMatrix value) async {
    matrix = value;
  }

  @override
  void invalidateCache() {}
}
