import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:langgry/features/auth/splash/pages/splash_screen.dart';
import 'package:langgry/features/knowledge/services/memory_knowledge_store.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/files/pages/file_parsing_screen.dart';
import 'package:langgry/features/knowledge/list/pages/dynamic_list_screen.dart';
import 'package:langgry/features/knowledge/memos/pages/memo_workspace_screen.dart';
import 'package:langgry/features/knowledge/workspace/pages/workspace_shell.dart';
import 'package:langgry/features/chat/models/chat_settings.dart';

void main() {
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
      MaterialApp(home: MemoWorkspaceScreen(store: store)),
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
      MaterialApp(
        home: SelectionModeScope(
          notifier: selectionMode,
          child: MemoWorkspaceScreen(store: store),
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
}
