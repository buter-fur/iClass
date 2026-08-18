// iClass 主界面冒烟测试：应用能正常构建出主界面。
import 'package:flutter_test/flutter_test.dart';

import 'package:iclass/app.dart';

void main() {
  testWidgets('主界面冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const IClassApp());
    await tester.pump();
    expect(find.text('iClass 课表'), findsOneWidget);
  });
}
