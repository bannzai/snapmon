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
  contentShared('content_shared'),

  /// タイトル画面を表示した (タイトルから写真を選んだ割合の分母)。
  titleShown('title_shown'),

  /// タイトル画面のボタンを押した (パラメータ `action`: album / camera / continue)。
  titleAction('title_action');

  const AnalyticsEvent(this.eventName);

  /// Analytics に送るイベント名。
  final String eventName;
}

/// 年齢の確認を通って Analytics の収集を始めたか。
/// iOS・Android は収集の既定を無効にできるが、Web の Analytics は最初の logEvent で初期化され識別子を作るため、
/// 収集を始めるまで SDK を呼ばない判定にこの値を使う。
var _analyticsCollectionStarted = false;

/// 年齢の確認を通った後に、[logAnalyticsEvent] が Analytics へ送るようにする。
/// lib/firebase/age_verified_session.dart の enableAnalyticsAndCrashlyticsCollection だけが呼ぶ。何度呼んでも同じ (冪等)。
void markAnalyticsCollectionStarted() {
  _analyticsCollectionStarted = true;
}

/// [logAnalyticsEvent] が Analytics へ送るのをやめる。
/// lib/firebase/age_verified_session.dart の endAgeVerifiedSessionWithFirebase だけが呼ぶ。何度呼んでも同じ (冪等)。
void markAnalyticsCollectionStopped() {
  _analyticsCollectionStarted = false;
}

/// [event] を Analytics に送る。[parameters] はイベントごとの補足 (値は文字列か数値)。
///
/// 年齢の確認を通るまで ([markAnalyticsCollectionStarted] の前) は Analytics の SDK を呼ばずに何もしない。
Future<void> logAnalyticsEvent({
  required AnalyticsEvent event,
  required Map<String, Object>? parameters,
}) async {
  if (!_analyticsCollectionStarted) {
    return;
  }
  await FirebaseAnalytics.instance.logEvent(
    name: event.eventName,
    parameters: parameters,
  );
}
