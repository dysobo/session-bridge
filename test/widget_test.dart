import 'package:flutter/widgets.dart';
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
}
