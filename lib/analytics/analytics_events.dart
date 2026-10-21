import 'package:firebase_analytics/firebase_analytics.dart';

/// 判定基準 (documents/DIRECTION.md「判定基準」) の計測元になる Analytics のイベント。
///
/// 名前は Analytics の制約 (英字始まり・英数字とアンダースコア・40 文字以内) に合わせる。
/// 名前を変えると過去の集計と繋がらなくなるため、変える時は判定基準の計測元の記述も同時に直す。
enum AnalyticsEvent {
  /// モンスターの生成が完了した (1 人あたりのモンスター生成数)。
  monsterGenerated('monster_generated'),

  /// バトルが完了した (1 人あたりのバトル数。勝敗を問わない)。
  battleCompleted('battle_completed'),

  /// 図鑑のカードかバトルの結果を共有した (目的「バズらせる」の共有数。判定基準へ足す候補)。
  contentShared('content_shared');

  const AnalyticsEvent(this.eventName);

  /// Analytics に送るイベント名。
  final String eventName;
}

/// [event] を Analytics に送る。[parameters] はイベントごとの補足 (値は文字列か数値)。
///
/// 年齢の確認を通るまで収集は無効のため (lib/firebase/age_verified_session.dart)、その前に呼んでも送られない。
Future<void> logAnalyticsEvent({
  required AnalyticsEvent event,
  required Map<String, Object>? parameters,
}) {
  return FirebaseAnalytics.instance.logEvent(
    name: event.eventName,
    parameters: parameters,
  );
}
