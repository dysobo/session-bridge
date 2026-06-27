import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_bridge/main.dart';

void main() {
  testWidgets('starts and accepts search input', (tester) async {
    await tester.pumpWidget(const SessionBridgeApp());
    expect(find.text('Session Bridge'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'codex');
    await tester.pump();

    expect(find.text('codex'), findsOneWidget);
  });

  testWidgets('restore dialog can open Codex Win or editable command', (
    tester,
  ) async {
    final session = AgentSession(
      source: SessionSource.codex,
      id: '019e2e86-c4a4-7203-b1a6-880ba0785a43',
      filePath: r'C:\Users\Administrator\.codex\sessions\sample.jsonl',
      cwd: r'H:\desk\app6',
      title: 'Sample session',
      summary: 'Sample summary',
      updatedAt: DateTime(2026, 5, 25, 10, 0),
      messageCount: 1,
      turns: const [ChatTurn(role: 'user', text: 'test')],
    );

    await tester.pumpWidget(
      SessionBridgeAppForTest(child: RestoreCommandDialog(session: session)),
    );

    expect(find.text('选择恢复方式'), findsOneWidget);
    expect(find.text('Codex Win'), findsOneWidget);
    expect(find.textContaining('codex://threads/019e2e86'), findsOneWidget);

    await tester.tap(find.text('PowerShell'));
    await tester.pumpAndSettle();

    expect(find.textContaining('codex resume'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'custom command');
    await tester.pump();

    expect(find.text('custom command'), findsOneWidget);
  });

  testWidgets('claude restore dialog uses PowerShell only', (tester) async {
    final session = AgentSession(
      source: SessionSource.claude,
      id: 'claude-session',
      filePath: r'C:\Users\Administrator\.claude\projects\sample.jsonl',
      cwd: r'H:\desk\app6',
      title: 'Claude session',
      summary: 'Sample summary',
      updatedAt: DateTime(2026, 5, 25, 10, 0),
      messageCount: 1,
      turns: const [ChatTurn(role: 'user', text: 'test')],
    );

    await tester.pumpWidget(
      SessionBridgeAppForTest(child: RestoreCommandDialog(session: session)),
    );

    expect(find.text('选择恢复方式'), findsOneWidget);
    expect(find.text('PowerShell'), findsOneWidget);
    expect(find.textContaining('claude --resume'), findsOneWidget);
    expect(find.textContaining('codex://threads/'), findsNothing);
  });

  testWidgets('settings dialog explains sync server URL', (tester) async {
    await tester.pumpWidget(
      SessionBridgeAppForTest(
        child: SettingsDialog(settings: AppSettings.defaults()),
      ),
    );

    expect(find.text('同步服务器 URL'), findsOneWidget);
    expect(find.textContaining('不是数据库地址'), findsOneWidget);
  });

  test('extracts AI message from OpenAI content blocks', () {
    final content = OpenAiCompatibleAnalyzer.extractAiMessage({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': '{"title":"ok"}'},
            ],
          },
        },
      ],
    });

    expect(content, '{"title":"ok"}');
  });

  test('extracts AI message from OpenAI string content', () {
    final content = OpenAiCompatibleAnalyzer.extractAiMessage({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': '{"title":"deepseek ok"}',
          },
        },
      ],
    });

    expect(content, '{"title":"deepseek ok"}');
  });

  test('extracts AI message from Anthropic-style content', () {
    final content = OpenAiCompatibleAnalyzer.extractAiMessage({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': '{"title":"mimo ok"}'},
      ],
    });

    expect(content, '{"title":"mimo ok"}');
  });

  test('extracts AI message from output text content', () {
    final content = OpenAiCompatibleAnalyzer.extractAiMessage({
      'output_text': '{"title":"responses ok"}',
    });

    expect(content, '{"title":"responses ok"}');
  });

  test('parses synced session payload', () {
    final session = SyncedSession.fromJson({
      'source': 'codex',
      'sessionId': 'abc',
      'relativePath': r'sessions\2026\sample.jsonl',
      'fileContentBase64': 'e30=',
      'aiTags': ['开发', ' ', '同步'],
      'category': '开发',
    });

    expect(session, isNotNull);
    expect(session!.source, SessionSource.codex);
    expect(session.relativePath, r'sessions\2026\sample.jsonl');
    expect(session.aiTags, ['开发', '同步']);
    expect(session.category, '开发');
  });

  test('builds Codex Win deep link', () {
    final session = sampleSession(
      id: '019e2e86-c4a4-7203-b1a6-880ba0785a43',
      title: 'Sample',
    );

    expect(
      session.codexWinDeepLink,
      'codex://threads/019e2e86-c4a4-7203-b1a6-880ba0785a43',
    );
  });

  test('parses synced session metadata without file content', () {
    final session = SyncedSession.fromJson({
      'source': 'claude',
      'sessionId': 'remote-1',
      'relativePath': r'project\remote-1.jsonl',
      'cwd': r'H:\desk',
      'title': 'Remote session',
      'summary': 'Remote summary',
      'updatedAt': '2026-06-05T12:00:00Z',
      'messageCount': 7,
      'contentBase64Length': 4096,
    }, requireContent: false);

    expect(session, isNotNull);
    expect(session!.source, SessionSource.claude);
    expect(session.displayTitle, 'Remote session');
    expect(session.cwd, r'H:\desk');
    expect(session.messageCount, 7);
    expect(session.contentBase64Length, 4096);
    expect(session.fileContentBase64, isEmpty);
  });

  testWidgets('download dialog can choose a single session', (tester) async {
    final sessions = [
      sampleSyncedSession(id: 'one'),
      sampleSyncedSession(id: 'two'),
    ];
    DownloadSyncChoice? selected;
    await tester.pumpWidget(
      SessionBridgeAppForTest(
        child: DownloadDialogTestHost(
          sessions: sessions,
          onChoice: (value) => selected = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '恢复').first);
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.full, isFalse);
    expect(selected!.sessions.single.id, 'one');
  });

  testWidgets('download dialog can choose full sync', (tester) async {
    final sessions = [
      sampleSyncedSession(id: 'one'),
      sampleSyncedSession(id: 'two'),
    ];
    DownloadSyncChoice? selected;
    await tester.pumpWidget(
      SessionBridgeAppForTest(
        child: DownloadDialogTestHost(
          sessions: sessions,
          onChoice: (value) => selected = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '全量同步'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.full, isTrue);
    expect(selected!.sessions, hasLength(2));
  });

  test('parses AI category plan and fills missing sessions', () {
    final sessions = [
      sampleSession(id: 'a', title: 'Flutter Android player'),
      sampleSession(id: 'b', title: 'Model unavailable test'),
    ];
    final plan = AiCategoryPlan.fromAiContent('''
      {
        "categories": [
          {"name": "客户端应用开发", "description": "客户端项目"}
        ],
        "assignments": [
          {"ref": "S001", "category": "客户端应用开发", "reason": "Flutter 客户端"}
        ]
      }
      ''', sessions);

    expect(plan.categories, kAiSessionCategories);
    expect(plan.assignments, hasLength(2));
    expect(plan.assignments.first.category, '客户端应用开发');
    expect(plan.assignments.last.category, kFallbackAiCategory);
    expect(plan.countsByCategory['客户端应用开发'], 1);
    expect(plan.countsByCategory[kFallbackAiCategory], 1);
  });

  test('normalizes invalid AI category to fallback', () {
    final sessions = [sampleSession(id: 'a', title: 'Unknown task')];
    final plan = AiCategoryPlan.fromAiContent('''
      {
        "assignments": [
          {"ref": "S001", "category": "临时新分类", "reason": "不确定"}
        ]
      }
      ''', sessions);

    expect(plan.assignments.single.category, kFallbackAiCategory);
  });
}

class SessionBridgeAppForTest extends StatelessWidget {
  const SessionBridgeAppForTest({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: child));
  }
}

class DownloadDialogTestHost extends StatefulWidget {
  const DownloadDialogTestHost({
    super.key,
    required this.sessions,
    required this.onChoice,
  });

  final List<SyncedSession> sessions;
  final ValueChanged<DownloadSyncChoice?> onChoice;

  @override
  State<DownloadDialogTestHost> createState() => _DownloadDialogTestHostState();
}

class _DownloadDialogTestHostState extends State<DownloadDialogTestHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final choice = await showDialog<DownloadSyncChoice>(
        context: context,
        builder: (context) => DownloadSyncDialog(sessions: widget.sessions),
      );
      widget.onChoice(choice);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

AgentSession sampleSession({required String id, required String title}) {
  return AgentSession(
    source: SessionSource.codex,
    id: id,
    filePath: 'C:\\Users\\Administrator\\.codex\\sessions\\$id.jsonl',
    cwd: r'H:\desk\app6',
    title: title,
    summary: 'Sample summary',
    updatedAt: DateTime(2026, 6, 5, 10, 0),
    messageCount: 1,
    turns: const [ChatTurn(role: 'user', text: 'sample task')],
  );
}

SyncedSession sampleSyncedSession({required String id}) {
  return SyncedSession(
    source: SessionSource.codex,
    id: id,
    relativePath: 'sessions\\$id.jsonl',
    title: 'Remote $id',
    summary: 'Remote summary $id',
    aiTitle: '',
    aiSummary: '',
    aiTags: const [],
    category: '测试/无效/其它',
    updatedAt: '2026-06-05T12:00:00Z',
    messageCount: 3,
    contentBase64Length: 4096,
  );
}
