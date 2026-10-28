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

  /// タイトル画面を表示した (タイトルから写真を選んだ割合の分母。ログインより前の分はログインが済んだ時に送るため、
  /// ログインまで進んだ人の表示数になる。扱いは documents/DIRECTION.md「決めたこと」の #46 の行)。
  titleShown('title_shown'),

  /// タイトル画面のボタンを押した (パラメータ `action`: album / camera / continue)。
  titleAction('title_action'),

  /// 初回の導線 (手持ちが空の時に写真を選んでそのまま戦う) の段階 (パラメータ `step`: [FirstExperienceStep] の名前。
  /// 送る時点は documents/DIRECTION.md「決めたこと」の #45 の行)。
  firstExperience('first_experience'),

  /// 撮る画面のカメラの権限の段階 (パラメータ `step`: [CameraPermissionStep] の名前。
  /// 送る時点は documents/DIRECTION.md「決めたこと」の #64 の行)。
  cameraPermission('camera_permission');

  const AnalyticsEvent(this.eventName);

  /// Analytics に送るイベント名。
  final String eventName;
}

/// 初回の導線の段階 (計測の `first_experience` の `step`)。
enum FirstExperienceStep {
  /// 写真を選んで生成の画面に入った。
  photoSelected('photo_selected'),

  /// モンスターが生まれ、対戦相手が決まった (「○○ があらわれた」)。
  matchmaking('matchmaking'),

  /// 初回のバトルの画面を開いた。
  battleStarted('battle_started'),

  /// 初回のバトルが決着した。
  battleCompleted('battle_completed'),

  /// 新しいモンスターが生まれなかった (生成しなかった・失敗・判定待ち・同じ被写体・呼び出しの例外)。
  generationFailed('generation_failed');

  const FirstExperienceStep(this.stepName);

  /// Analytics に送る `step` の値。
  final String stepName;
}

/// 撮る画面のカメラの権限の段階 (計測の `camera_permission` の `step`)。
enum CameraPermissionStep {
  /// 撮るボタン・「カメラを使う」・「もう一度試す」を押してカメラを求めた。
  requested('requested'),

  /// 求めた後か設定を開いた後に、カメラを開けた。
  granted('granted'),

  /// 求めた後か設定を開いた後に、権限が無くてカメラを開けなかった。
  denied('denied'),

  /// 権限が無い時の「設定を開く」を押した。
  openSettings('open_settings');

  const CameraPermissionStep(this.stepName);

  /// Analytics に送る `step` の値。
  final String stepName;
}

/// ログインして Analytics の収集を始めたか。
/// iOS・Android は収集の既定を無効にできるが、Web の Analytics は最初の logEvent で初期化され識別子を作るため、
/// 収集を始めるまで SDK を呼ばない判定にこの値を使う。
var _analyticsCollectionStarted = false;

/// ログインの後に、[logAnalyticsEvent] が Analytics へ送るようにする。
/// lib/firebase/session.dart の enableAnalyticsAndCrashlyticsCollection だけが呼ぶ。何度呼んでも同じ (冪等)。
void markAnalyticsCollectionStarted() {
  _analyticsCollectionStarted = true;
}

/// [logAnalyticsEvent] が Analytics へ送るのをやめる。
/// lib/firebase/session.dart の endSessionWithFirebase だけが呼ぶ。何度呼んでも同じ (冪等)。
void markAnalyticsCollectionStopped() {
  _analyticsCollectionStarted = false;
}

/// [event] を Analytics に送る。[parameters] はイベントごとの補足 (値は文字列か数値)。
///
/// ログインするまで ([markAnalyticsCollectionStarted] の前) と DEBUG ビルドでログインを飛ばした時は Analytics の SDK を呼ばずに何もしない。
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
