import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/analytics/analytics_events.dart';

void main() {
  test('イベント名は Analytics の制約 (英字始まり・英数字とアンダースコア・40 文字以内) を満たし、重複しない', () {
    final eventNames = AnalyticsEvent.values.map((event) => event.eventName);
    for (final eventName in eventNames) {
      expect(eventName, matches(RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$')));
      expect(eventName, isNot(startsWith('firebase_')));
    }
    expect(eventNames.toSet().length, AnalyticsEvent.values.length);
  });

  test(
    '収集を始める前は Analytics の SDK を呼ばずに終わる (Firebase を初期化していなくても例外にならない)',
    () async {
      await logAnalyticsEvent(
        event: AnalyticsEvent.monsterGenerated,
        parameters: null,
      );
    },
  );
}
