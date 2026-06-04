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

  testWidgets('restore dialog shows editable command', (tester) async {
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

    expect(find.text('确认恢复命令'), findsOneWidget);
    expect(find.textContaining('codex resume'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'custom command');
    await tester.pump();

    expect(find.text('custom command'), findsOneWidget);
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
