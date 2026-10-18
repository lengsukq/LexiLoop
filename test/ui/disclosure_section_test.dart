import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';

void main() {
  testWidgets('折叠保留输入，内部滚动与展开状态互不覆盖', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LexiTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: DisclosureSection(
              title: '详情',
              child: Column(
                children: <Widget>[
                  TextField(),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1800,
                      height: 60,
                      child: Text('横向明细'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留的笔记');
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('保留的笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
