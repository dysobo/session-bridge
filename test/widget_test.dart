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
}

class SessionBridgeAppForTest extends StatelessWidget {
  const SessionBridgeAppForTest({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: child));
  }
}
