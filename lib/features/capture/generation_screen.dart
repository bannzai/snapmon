import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../common_ui/scene_route.dart';

import 'package:flutter/services.dart';

import '../../analytics/analytics_events.dart';
import '../../l10n/l10n.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../common_ui/square_icon_button.dart';
import '../battle/battle_recorder.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../opponent/pvp_client.dart';
import '../opponent/random_cpu_battle.dart';
import '../result/result_screen.dart';
import '../share/card_sharer.dart';
import 'first_battle.dart';
import 'monster_generator.dart';
import 'square_crop_editor.dart';
import 'subject_mask.dart';
import 'ticket_purchase_sheet.dart';

/// 生成の直後に図鑑の反映を待つ時間。Firestore のスナップショットは保存から 1 秒前後で届くため、通信が遅い時の余裕を見た値。
const Duration _monsterArrivalTimeout = Duration(seconds: 30);

/// 初回の導線で「○○ があらわれた」を出してからバトルの画面を開くまでの時間。
/// 相手の名前 (表示名は 12 文字まで) を読み切れ、待たされたと感じない長さにした。
const Duration _opponentRevealDuration = Duration(milliseconds: 1500);

/// 生成が途中の状態 (processing・pending_judge) で返った後に、結果を取り直し続ける長さ。
/// owner の指定 (https://github.com/bannzai/snapmon/issues/218)。これを過ぎても終わらない時は「もう少し待ってね」を出す。
/// 取り直した回数で数えるため、実際の経過は取り直しの通信の時間の分だけこれより長くなる。
const Duration _pollingDuration = Duration(seconds: 40);

/// 途中の状態の結果を取り直す間隔。取り直しは Functions の呼び出しではなく生成のレコード 1 件の Firestore の読み取り
/// ([MonsterGenerator.fetchGeneration]) で、40 秒の間に 8 回の読み取りに収まる。サーバーの段階は数秒〜数十秒で進むため、
/// 終わってから画面に出るまでの遅れが 5 秒以内なら待たされたと感じにくい。
const Duration _pollingInterval = Duration(seconds: 5);

/// 直前の setState の表示が画面に出るまで待つ。Web の `compute` は別の isolate を使わず同じスレッドで動くため、
/// ボタンを押した直後に重い画像の処理を始めると、押した後の待ちの表示が描かれないまま画面が止まる (#302)。
/// フレームを描き終えた後もマイクロタスクのうちはブラウザが画面に出さないため、タイマーで 1 回イベントループに戻す。
Future<void> _waitUntilPainted() async {
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration.zero);
}

/// 写真 1 枚から生成する画面。写真を整えて送り、段階ごとの待ち時間を出し、結果に応じて生まれた画面を開くか、
/// 判定待ち・生成しなかった理由・エラーを出す。生まれた画面を閉じたら、その画面の [ResultScreenAction] を返して閉じる。
///
/// 送る前に被写体の範囲を決める。[letsUserChooseSubjectRange] なら、OS の切り出し ([MonsterGenerator.createSubjectMask]) が
/// 被写体を見つけた時は切り出した絵と元の写真を並べ、切り抜いた絵で作るか正方形の枠で範囲を決めるかを選んでもらい
/// (自動では切り抜かない。#242)、見つからない・使えない時は正方形の枠で範囲を決めてもらう。
/// [letsUserChooseSubjectRange] でなければ、操作を挟まず OS の切り出しのマスクで、それも無ければマスク無し (写真全体) で送る。
///
/// 初回の導線 ([startsFirstBattle]) では、生成を待つ間は「相手を探しています」を出し、生まれたら手持ちに入れて相手を決め、
/// 「○○ があらわれた」の後にバトルの画面を開く。バトルの画面を閉じたら、図鑑を見る時は [ResultScreenAction.openDex]、
/// それ以外 (手持ちを増やす) は null を返して閉じる。「もう一回対戦する」で閉じた時は別の CPU の相手との対戦を続けて開き、
/// それを閉じた時に同じ規則で閉じる。生まれなかった時は初回でない時と同じ理由の表示に戻る。
class GenerationScreen extends StatefulWidget {
  /// 生成の画面を作る。
  const GenerationScreen({
    super.key,
    required this.sourcePhoto,
    required this.photoSource,
    required this.letsUserChooseSubjectRange,
    required this.monsterGenerator,
    required this.dexStore,
    required this.cardSharer,
    required this.startsFirstBattle,
    required this.sampleData,
    required this.pvpClient,
    required this.battleRecorder,
  });

  /// 初回の導線 (生まれたらそのまま戦う) にするか。呼び出し元が写真を選んだ時点の手持ちが空か ([DexStore.party]) で決める。
  /// 生まれた時に手持ちが空でなくなっていた (Firestore の手持ちが後から届いた) 時は、初回でない時と同じく生まれた画面を開く。
  final bool startsFirstBattle;

  /// 見本データ (初回のバトルの CPU トレーナー)。
  final SampleData sampleData;

  /// 初回のバトルの前の定義の読み直しに渡す。
  final PvpClient pvpClient;

  /// 初回のバトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 撮った・選んだ写真の中身。
  final Uint8List sourcePhoto;

  /// 写真がどこから来たか。
  final GenerationPhotoSource photoSource;

  /// 被写体の範囲を利用者に決めてもらうか (OS の切り出しが被写体を見つけた時は切り抜くかを選び、見つけられない・使えない時は
  /// 正方形の枠で範囲を決める)。false なら操作を挟まず、OS の切り出しのマスクか、それも無ければマスク無し (写真全体) で送る
  /// (開発者メニューの見本の写真は、操作を挟まずに生成まで通すため false にする)。
  final bool letsUserChooseSubjectRange;

  /// 生成の呼び出しと計測。
  final MonsterGenerator monsterGenerator;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 生まれた画面からの図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

/// 生成の画面の状態。
enum _GenerationPhase {
  /// 写真を整えている・被写体を探している・送っている・サーバーが処理している・途中の状態の結果を取り直している。
  inProgress,

  /// OS の切り出しが被写体を見つけ、切り抜いた絵で作るか正方形の枠で範囲を決めるかを選んでもらっている。
  choosingCutout,

  /// 正方形の枠で範囲を決めてもらっている (OS の切り出しが被写体を見つけられなかった・使えなかった時と、切り抜かないと選んだ時)。
  choosingRange,

  /// 結果を [_pollingDuration] の間取り直しても、サーバーが判定を待っている (pending_judge) か、まだ処理している。
  waiting,

  /// 写真から生成しなかった・生成に失敗した。
  notGenerated,

  /// 呼び出しが例外で終わった。
  error,

  /// 初回の導線で、写真の被写体のモンスターがもう図鑑にいた (同じ被写体・同じ写真の撮り直し)。
  alreadyInDex,

  /// 初回の導線で、対戦相手が決まった (「○○ があらわれた」)。
  opponentFound,
}

class _GenerationScreenState extends State<GenerationScreen> {
  /// 写真 1 枚に 1 つの要求 ID。送り直し・読み直しにも同じ ID を使う ([MonsterGenerator.createRequestID])。
  late final String _requestID = widget.monsterGenerator.createRequestID();

  Uint8List? _preparedPhoto;

  /// 決めたマスクの出どころ。決まるまでは null (もう一度試す時に、範囲を決め直させないための目印)。
  GenerationMaskSource? _maskSource;

  /// 送るマスク。[GenerationMaskSource.none] の時は null。
  Uint8List? _mask;

  /// マスクで切り出した絵のプレビュー。マスクが無い時は null (写真をそのまま出す)。
  Uint8List? _cutoutPreview;

  /// OS の切り出しが見つけた被写体のマスクと、それで切り出した絵のプレビュー。切り抜くかを選んでもらう間
  /// ([_GenerationPhase.choosingCutout]) に使い、切り抜くと選んだら [_mask]・[_cutoutPreview] に移す。見つけていない時は null。
  ({Uint8List mask, Uint8List cutoutPreview})? _subjectCutout;

  /// 範囲を決めている写真の画素の大きさ ([_GenerationPhase.choosingRange] の間だけ使う)。
  ({int width, int height})? _photoSize;

  /// 範囲を決める画面の今の枠。範囲を決める画面を出す前は null。
  SquareCrop? _crop;

  /// OS の切り出しが失敗した時のエラー。範囲を決める画面に出す。
  Object? _subjectMaskError;

  /// 写真とマスクを送り終えたか。
  bool _isUploaded = false;

  /// 購入画面を出す処理の途中か (package の取得中と購入画面を出している間)。
  bool _isOfferingTicketPurchase = false;
  GenerationStage? _completedStage;
  _GenerationPhase _phase = _GenerationPhase.inProgress;
  GenerationResult? _result;
  Object? _error;

  /// 画面を開いた時の [GenerationScreen.startsFirstBattle]。呼び出し元は手持ちの有無から決めて渡し、経路が作り直されると
  /// 手持ちに入れた後の値で渡し直されるため、開いた時の値で固定する。
  late final bool _startsFirstBattle = widget.startsFirstBattle;

  /// 初回の導線で、写真の被写体のモンスターがもう図鑑にいた時のそのモンスター ([_GenerationPhase.alreadyInDex])。
  OwnedMonster? _alreadyInDexMonster;

  /// 初回の導線で戦うと決めたモンスター。決まるまでは null (例外の後の「もう一度試す」を、生成ではなく対戦の準備のやり直しにする目印)。
  OwnedMonster? _firstBattleMonster;

  /// 初回の導線の対戦相手。決まるまでは null。
  FirstBattleOpponent? _firstBattleOpponent;

  /// 初回のバトルの画面に出す自分のアイコンと表示名。読む前・ログインが無い時・読めなかった時は null で、バトルの画面に出さない。
  PlayerProfile? _playerProfile;

  /// 最新の初回のバトルの準備の番号。「もう一度試す」の前の準備のプロフィールが後から届いても反映しないために照合する。
  int _latestFirstBattlePreparationNumber = 0;

  /// 初回のバトルの画面を開いたか (「○○ があらわれた」の演出の終わりで 1 回だけ開くため)。
  bool _hasOpenedFirstBattle = false;

  /// 「○○ があらわれた」を出してからバトルの画面を開くまでの待ち。演出の進捗バーは ListView の中にあり、
  /// 端末の文字が大きいと画面外で作られず終わりを知らせないため、バトルを開くきっかけは State に持つ。
  Timer? _openFirstBattleTimer;

  /// 途中の状態の結果を取り直すまでの待ち。画面を閉じた時に止めるため State に持つ。
  Timer? _pollingTimer;

  @override
  void dispose() {
    _openFirstBattleTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// 初回のバトルの乱数の seed (相手の選び方とバトルの展開)。値の範囲は DeterministicRandom の状態 (32 bit) に合わせた。
  /// Web (JavaScript) ではシフトが 32 bit に切り詰められ `1 << 32` が 0 になるため、上限は整数リテラルで書く
  final int _firstBattleRandomSeed = math.Random().nextInt(0x100000000);

  @override
  void initState() {
    super.initState();
    if (_startsFirstBattle) {
      _logFirstExperience(step: FirstExperienceStep.photoSelected);
    }
    // 画面に入る前に setState を呼ばないため、最初のフレームの後に始める
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  /// 初回の導線の段階 [step] を送る。計測の失敗は画面の進み方に影響させない。
  void _logFirstExperience({required FirstExperienceStep step}) => unawaited(
    widget.monsterGenerator
        .logEvent(
          event: AnalyticsEvent.firstExperience,
          parameters: {'step': step.stepName},
        )
        .catchError((Object _) {}),
  );

  /// 済んでいない手順 (写真を整える・範囲を決める・送る) から生成を進める。もう一度試す時も同じ要求 ID で呼び直す。
  /// 範囲を決めてもらう時は [_GenerationPhase.choosingRange] にして止まり、決まったら [_confirmCrop] から呼び直される。
  /// 切り抜くかを選んでもらう時は [_GenerationPhase.choosingCutout] にして止まり、切り抜くと選んだら [_useSubjectCutout] から
  /// 呼び直される (範囲を自分で決めると選んだら [_GenerationPhase.choosingRange] に移る)。
  Future<void> _generate() async {
    setState(() {
      _phase = _GenerationPhase.inProgress;
      _error = null;
    });
    try {
      final preparedPhoto =
          _preparedPhoto ??
          await widget.monsterGenerator.preparePhoto(
            sourceBytes: widget.sourcePhoto,
          );
      if (!mounted) {
        return;
      }
      setState(() => _preparedPhoto = preparedPhoto);
      if (_maskSource == null && !await _decideMask(photo: preparedPhoto)) {
        return;
      }
      if (!mounted) {
        return;
      }
      if (!_isUploaded) {
        await widget.monsterGenerator.uploadPhoto(
          requestID: _requestID,
          photo: preparedPhoto,
        );
        if (_mask case final mask?) {
          await widget.monsterGenerator.uploadMask(
            requestID: _requestID,
            mask: mask,
          );
        }
        _isUploaded = true;
      }
      await _handleResult(
        result: await widget.monsterGenerator.requestGeneration(
          requestID: _requestID,
          maskSource: _maskSource!,
          onCompletedStage: ({required completedStage}) {
            if (mounted) {
              setState(() => _completedStage = completedStage);
            }
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        _logFirstExperienceFailureIfNeeded();
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
          // サーバーが写真を見つけられなかった (受け付けを断られた写真を消した) 時は、次に試す時に置き直す
          if (error is GenerationPhotoMissingException ||
              error is GenerationDailyLimitException) {
            _isUploaded = false;
          }
        });
        if (error is GenerationDailyLimitException) {
          unawaited(_offerTicketPurchaseAndRetry());
        }
      }
    }
  }

  /// 上限に当たった時に、売っていれば購入画面を出し、利用者が続けると決めたら同じ写真で生成をやり直す。
  /// 売っていない間は何もしない (上限のエラーの表示のまま)。
  Future<void> _offerTicketPurchaseAndRetry() async {
    // package の取得中に「もう一度試す」でまた上限に当たっても、購入画面を重ねない
    if (_isOfferingTicketPurchase) {
      return;
    }
    _isOfferingTicketPurchase = true;
    final bool continuesGeneration;
    try {
      continuesGeneration = await offerTicketPurchase(
        context: context,
        monsterGenerator: widget.monsterGenerator,
        isDailyLimitShown: () =>
            _phase == _GenerationPhase.error &&
            _error is GenerationDailyLimitException,
      );
    } finally {
      _isOfferingTicketPurchase = false;
    }
    if (continuesGeneration && mounted) {
      await _generate();
    }
  }

  /// OS の切り出しで [photo] のマスクを決める。決まった (範囲を決めてもらわない設定で、被写体が見つかった・マスク無しにした) 時は true、
  /// 切り抜くかを選んでもらう画面か範囲を決めてもらう画面にした時は false を返す。
  Future<bool> _decideMask({required Uint8List photo}) async {
    // 範囲を決めた後の失敗 (crop のマスクを作れなかった) からもう一度試す時は、OS の切り出しをやり直さず決めた枠のまま範囲を決める画面に戻す
    if (_crop != null) {
      setState(() => _phase = _GenerationPhase.choosingRange);
      return false;
    }
    Uint8List? subjectMask;
    Object? subjectMaskError;
    try {
      subjectMask = await widget.monsterGenerator.createSubjectMask(
        photo: photo,
      );
    } on PlatformException catch (error) {
      subjectMaskError = error;
    } on MissingPluginException catch (error) {
      subjectMaskError = error;
    }
    if (subjectMask case final foundSubjectMask?) {
      final cutoutPreview = await widget.monsterGenerator.createCutoutPreview(
        photo: photo,
        mask: foundSubjectMask,
      );
      if (!mounted) {
        return false;
      }
      if (!widget.letsUserChooseSubjectRange) {
        setState(() {
          _maskSource = GenerationMaskSource.iosSubject;
          _mask = foundSubjectMask;
          _cutoutPreview = cutoutPreview;
        });
        return true;
      }
      setState(() {
        _subjectCutout = (mask: foundSubjectMask, cutoutPreview: cutoutPreview);
        _phase = _GenerationPhase.choosingCutout;
      });
      return false;
    }
    if (!widget.letsUserChooseSubjectRange) {
      if (mounted) {
        setState(() => _maskSource = GenerationMaskSource.none);
      }
      return true;
    }
    if (mounted) {
      _startChoosingRange(photo: photo, subjectMaskError: subjectMaskError);
    }
    return false;
  }

  /// [photo] の上で正方形の枠で範囲を決めてもらう画面にする。[subjectMaskError] (OS の切り出しが失敗した時のエラー) があれば画面に出す。
  /// [photo] が読めない形式なら [FormatException] を投げる。
  void _startChoosingRange({
    required Uint8List photo,
    required Object? subjectMaskError,
  }) {
    final photoSize = photoPixelSize(photo: photo);
    setState(() {
      _photoSize = photoSize;
      _crop = initialSquareCrop(
        photoWidth: photoSize.width,
        photoHeight: photoSize.height,
      );
      _subjectMaskError = subjectMaskError;
      _phase = _GenerationPhase.choosingRange;
    });
  }

  /// OS の切り出しで切り抜いた絵 ([_subjectCutout]) で生成を続ける。
  Future<void> _useSubjectCutout() {
    final subjectCutout = _subjectCutout!;
    setState(() {
      _maskSource = GenerationMaskSource.iosSubject;
      _mask = subjectCutout.mask;
      _cutoutPreview = subjectCutout.cutoutPreview;
    });
    return _generate();
  }

  /// 決めた枠 ([_crop]) をマスクにして、生成を続ける。
  Future<void> _confirmCrop() async {
    final photo = _preparedPhoto!;
    setState(() => _phase = _GenerationPhase.inProgress);
    try {
      await _waitUntilPainted();
      final mask = await widget.monsterGenerator.createSquareMask(
        photo: photo,
        crop: _crop!,
      );
      final cutoutPreview = await widget.monsterGenerator.createCutoutPreview(
        photo: photo,
        mask: mask,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _maskSource = GenerationMaskSource.crop;
        _mask = mask;
        _cutoutPreview = cutoutPreview;
      });
    } catch (error) {
      if (mounted) {
        _logFirstExperienceFailureIfNeeded();
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
        });
      }
      return;
    }
    await _generate();
  }

  /// 初回の導線で、戦うモンスターが決まる前に生成が終わらなかった時に `generation_failed` を送る。
  void _logFirstExperienceFailureIfNeeded() {
    if (_startsFirstBattle && _firstBattleMonster == null) {
      _logFirstExperience(step: FirstExperienceStep.generationFailed);
    }
  }

  /// 初回の導線で [monster] を手持ちに入れ、対戦相手を決めて「○○ があらわれた」を出す。
  /// 例外の後の「もう一度試す」もここからやり直す (生成は済んでいるため呼び直さない)。
  Future<void> _prepareFirstBattle({required OwnedMonster monster}) async {
    _latestFirstBattlePreparationNumber += 1;
    setState(() {
      _firstBattleMonster = monster;
      _phase = _GenerationPhase.inProgress;
      _error = null;
    });
    try {
      await widget.dexStore.addToParty(monsterID: monster.definition.id);
      // 手持ちの保存が済んでから相手を決める (CPU トレーナーの手持ちのレベルは手持ちに入れた後の平均に合わせるため)
      if (!widget.dexStore.isInParty(monsterID: monster.definition.id)) {
        throw StateError('${monster.definition.name} を手持ちに入れられませんでした');
      }
      // 相手を決める間に並べて読む。レコードの .wait は例外を ParallelWaitError に包み、画面に出す文言が変わるため、
      // 元の例外をそのまま投げる Future.wait を使う。eagerError: 札にだけ使うプロフィールの応答を待たずにエラーを出すため
      await Future.wait<void>([
        _loadPlayerProfile(
          preparationNumber: _latestFirstBattlePreparationNumber,
        ),
        prepareFirstBattleOpponent(
          dexStore: widget.dexStore,
          pvpClient: widget.pvpClient,
          sampleData: widget.sampleData,
          randomSeed: _firstBattleRandomSeed,
        ).then((opponent) => _firstBattleOpponent = opponent),
      ], eagerError: true);
      if (!mounted) {
        return;
      }
      _logFirstExperience(step: FirstExperienceStep.matchmaking);
      setState(() => _phase = _GenerationPhase.opponentFound);
      _openFirstBattleTimer?.cancel();
      _openFirstBattleTimer = Timer(_opponentRevealDuration, _openFirstBattle);
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
        });
      }
    }
  }

  /// 自分のプロフィールを読んで [_playerProfile] に置く。バトルの画面の札にだけ使うため、読めない時は例外を投げずに null を置く
  /// (バトルは止めない)。[preparationNumber] が最新の準備でなくなった後に届いた結果は置かない。
  Future<void> _loadPlayerProfile({required int preparationNumber}) async {
    PlayerProfile? playerProfile;
    try {
      playerProfile = await widget.pvpClient.fetchProfile();
    } catch (error) {
      debugPrint('プロフィールを読めませんでした: $error');
    }
    if (preparationNumber == _latestFirstBattlePreparationNumber) {
      _playerProfile = playerProfile;
    }
  }

  /// 決まった相手との初回のバトルの画面を開き、閉じたらこの画面も閉じる (「もう一回対戦する」の対戦を続けた時は、その後に閉じる)。
  Future<void> _openFirstBattle() async {
    final opponent = _firstBattleOpponent;
    final monster = _firstBattleMonster;
    // 演出の終わりまでに閉じられた (閉じている途中の) 画面からはバトルを開かない
    if (_hasOpenedFirstBattle ||
        opponent == null ||
        monster == null ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    _hasOpenedFirstBattle = true;
    _logFirstExperience(step: FirstExperienceStep.battleStarted);
    final dexStore = widget.dexStore;
    // 経路が作り直されると builder が呼び直されるため、決着の後にレベルが上がった手持ちを渡し直さないよう、開く時の手持ちで固定する
    final playerParty = List.of(dexStore.party);
    var battleRoute = sceneRoute<BattleScreenAction>(
      builder: (context) => BattleScreen(
        playerParty: playerParty,
        opponentParty: opponent.cpuOpponent.opponentParty,
        opponentKind: BattleOpponentKind.cpu,
        definitions: opponent.definitions,
        randomSeed: _firstBattleRandomSeed,
        battleRecorder: widget.battleRecorder,
        onPlayerLevelsChanged: dexStore.updateLevels,
        cardSharer: widget.cardSharer,
        firstBattleBornMonster: monster,
        firstBattleMonsterIsNewlyBorn:
            monster.definition.id != _alreadyInDexMonster?.definition.id,
        playerProfile: _playerProfile,
        opponentDisplayName: opponent.cpuOpponent.opponentName,
      ),
    );
    var action = await Navigator.of(context).push(battleRoute);
    // 2 戦目からは初回の導線の計測 (first_experience) を送らない (prepareRandomCpuBattleScreen は firstBattleBornMonster を null にする)
    while (action == BattleScreenAction.rematch) {
      // 準備の間に前の相手の「○○ があらわれた」を出したままにすると、乱数で選び直す次の相手と名前が食い違うため、相手を探す表示に戻す
      if (mounted) {
        setState(() => _phase = _GenerationPhase.inProgress);
      }
      final BattleScreen battleScreen;
      try {
        battleScreen = await prepareRandomCpuBattleScreen(
          dexStore: dexStore,
          pvpClient: widget.pvpClient,
          sampleData: widget.sampleData,
          battleRecorder: widget.battleRecorder,
          cardSharer: widget.cardSharer,
          playerProfile: _playerProfile,
        );
      } catch (error) {
        // 定義を読み直せない時はエラーをそのまま出し、この画面を閉じる (撮る画面に戻り、対戦のシーンから挑み直せる)
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
        break;
      }
      // 前のバトルの画面が閉じる演出を終えて破棄されるまで待つ。待たずに開くと、新しいバトルの画面が BGM を流した後に
      // 前の画面の破棄がホームの BGM に戻し、2 戦目でホームの BGM が流れるため
      await battleRoute.completed;
      // 最初のバトルを開く時と同じく、準備を待つ間に閉じられた (閉じる演出の途中の) 画面からはバトルを開かない
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      battleRoute = sceneRoute<BattleScreenAction>(
        builder: (context) => battleScreen,
      );
      action = await Navigator.of(context).push(battleRoute);
    }
    // 再戦の準備の間に閉じられた (閉じる演出の途中の) 画面からもう一度 pop すると、下の画面まで閉じてしまうため、前面にある時だけ閉じる
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop(
        action == BattleScreenAction.openDex
            ? ResultScreenAction.openDex
            : null,
      );
    }
  }

  /// 人が写っている写真から生まれた時の注意 (モンスターの画像は対戦で他の人にも見える・他人が写る時は同意を得る) を出し、閉じるまで待つ。
  /// 人が写る写真は拒否せず注意で許容する (documents/DIRECTION.md「決めたこと」2026-11-07 の #198 の行)。
  Future<void> _showPersonNotice() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.generationPersonNoticeTitle),
      content: Text(context.l10n.generationPersonNoticeMessage),
      actions: [
        FilledButton(
          key: const Key('person-notice-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonClose),
        ),
      ],
    ),
  );

  /// 判定待ちの生成の結果を読み直す。まだ途中の状態なら、もう一度 [_pollingDuration] の間取り直す。
  Future<void> _fetchAgain() async {
    setState(() {
      _phase = _GenerationPhase.inProgress;
      _error = null;
    });
    try {
      await _handleResult(
        // 同じ写真の別の要求の結果を使い回した時は、送った ID のレコードは無く、使い回し先の ID のレコードを読む
        result: await widget.monsterGenerator.fetchGeneration(
          requestID: _result?.requestID ?? _requestID,
        ),
      );
    } catch (error) {
      if (mounted) {
        _logFirstExperienceFailureIfNeeded();
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
        });
      }
    }
  }

  /// 途中の状態 ([_result]) を受け取った後、処理中の表示のまま [_pollingInterval] ごとに結果を取り直し、終了状態になったら
  /// [_handleResult] に渡す。[_pollingDuration] の間に終わらなければ「もう少し待ってね」([_GenerationPhase.waiting]) にする。
  /// 取り直しの例外はそのまま投げる (呼び出し元がエラーの表示にする)。画面を閉じたら取り直しをやめる。
  Future<void> _pollUntilFinished() async {
    setState(() => _phase = _GenerationPhase.inProgress);
    for (
      var pollingCount = 0;
      pollingCount < _pollingDuration.inSeconds ~/ _pollingInterval.inSeconds;
      pollingCount++
    ) {
      await _waitPollingInterval();
      if (!mounted) {
        return;
      }
      // 同じ写真の別の要求の結果を使い回した時は、送った ID のレコードは無く、使い回し先の ID のレコードを読む
      final polledResult = await widget.monsterGenerator.fetchGeneration(
        requestID: _result?.requestID ?? _requestID,
      );
      if (!mounted) {
        return;
      }
      if (polledResult.status != GenerationStatus.processing &&
          polledResult.status != GenerationStatus.pendingJudge) {
        await _handleResult(result: polledResult);
        return;
      }
      setState(() => _result = polledResult);
    }
    _logFirstExperienceFailureIfNeeded();
    setState(() => _phase = _GenerationPhase.waiting);
  }

  /// [_pollingInterval] だけ待つ。画面を閉じて [_pollingTimer] を止めた時は完了しない (呼び出し元の取り直しはそこで止まる)。
  Future<void> _waitPollingInterval() {
    final completer = Completer<void>();
    _pollingTimer = Timer(_pollingInterval, completer.complete);
    return completer.future;
  }

  /// [result] に応じて、生まれた画面を開くか、判定待ち・生成しなかった理由を出す。
  /// 初回の導線では、新しく生まれたらそのまま初回のバトルの準備に進み、もう図鑑にいた時はそのことと戦う操作を出す。
  Future<void> _handleResult({required GenerationResult result}) async {
    if (!mounted) {
      return;
    }
    setState(() => _result = result);
    switch (result.status) {
      case GenerationStatus.saved || GenerationStatus.duplicate:
        // 同じ写真の別の要求の結果を使い回した時は、送った要求 ID と違う ID が返る (functions/src/generation/pipeline.ts)。
        // その時と同じ被写体 (duplicate) の時は、新しく生まれず図鑑にいるモンスターを開く
        final isNewlyBorn =
            result.status == GenerationStatus.saved &&
            result.requestID == _requestID;
        final monster = await widget.dexStore.waitForMonster(
          monsterID: result.monsterID!,
          timeout: _monsterArrivalTimeout,
        );
        if (isNewlyBorn) {
          await widget.monsterGenerator
              .logEvent(
                event: AnalyticsEvent.monsterGenerated,
                parameters: {'source': widget.photoSource.name},
              )
              // 計測の失敗は生まれた画面の表示に影響させない
              .catchError((Object _) {});
        }
        if (!mounted) {
          return;
        }
        // duplicate で開くのは前に生まれたモンスターで、今回の写真の画像は他の人に見えないため注意は出さない
        if (result.status == GenerationStatus.saved && result.personDetected) {
          await _showPersonNotice();
        }
        if (!mounted) {
          return;
        }
        final dexStore = widget.dexStore;
        if (_startsFirstBattle &&
            dexStore.party.isEmpty &&
            dexStore.hasPartyVacancy) {
          if (isNewlyBorn) {
            await _prepareFirstBattle(monster: monster);
          } else {
            _logFirstExperience(step: FirstExperienceStep.generationFailed);
            setState(() {
              _alreadyInDexMonster = monster;
              _phase = _GenerationPhase.alreadyInDex;
            });
          }
          return;
        }
        final action = await Navigator.of(context).push(
          sceneRoute<ResultScreenAction>(
            builder: (context) => ResultScreen(
              monster: monster,
              dexStore: widget.dexStore,
              origin: isNewlyBorn
                  ? ResultScreenOrigin.newlyBorn
                  : ResultScreenOrigin.alreadyInDex,
              cardSharer: widget.cardSharer,
            ),
          ),
        );
        if (mounted) {
          Navigator.of(context).pop(action);
        }
      case GenerationStatus.processing || GenerationStatus.pendingJudge:
        await _pollUntilFinished();
      case GenerationStatus.rejected || GenerationStatus.failed:
        _logFirstExperienceFailureIfNeeded();
        setState(() => _phase = _GenerationPhase.notGenerated);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              SquareIconButton(
                icon: Icons.close,
                tooltip: context.l10n.commonClose,
                onPressed: () => Navigator.of(context).pop(),
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_phase == _GenerationPhase.choosingRange)
            SquareCropEditor(
              photo: _preparedPhoto!,
              photoWidth: _photoSize!.width,
              photoHeight: _photoSize!.height,
              crop: _crop!,
              onCropChanged: ({required crop}) => setState(() => _crop = crop),
            )
          else if (_phase == _GenerationPhase.choosingCutout)
            _CutoutChoicePreview(
              cutoutPreview: _subjectCutout!.cutoutPreview,
              photo: _preparedPhoto!,
            )
          else
            Center(
              child: SizedBox.square(
                dimension: 200,
                child: ClipRRect(
                  borderRadius: SnapmonRadii.card,
                  child: switch (_cutoutPreview) {
                    // 切り出した絵は形を崩さず、透明な背景を地の色で見せる
                    final cutoutPreview? => ColoredBox(
                      key: const Key('cutout-preview'),
                      color: SnapmonColors.artBackground,
                      child: Image.memory(
                        cutoutPreview,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                    null => Image.memory(
                      _preparedPhoto ?? widget.sourcePhoto,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // 整える前の写真が読めない形式 (HEIC 等) でも、画面は壊さず枠だけを出す
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(color: SnapmonColors.surfaceRaised),
                    ),
                  },
                ),
              ),
            ),
          const SizedBox(height: 28),
          ..._buildPhaseContent(l10n: context.l10n),
        ],
      ),
    ),
  );

  List<Widget> _buildPhaseContent({
    required AppLocalizations l10n,
  }) => switch (_phase) {
    // 初回の導線は生成を待つ間も相手を探している見せ方にし、生成の段階は小さく添える
    _GenerationPhase.inProgress when _startsFirstBattle => [
      Text(
        l10n.generationSearchingOpponent,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        _firstBattleMonster == null
            ? _inProgressText(l10n: l10n)
            : l10n.generationBattleWith(_firstBattleMonster!.definition.name),
        key: const Key('matchmaking-stage'),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 24),
      const Center(child: CircularProgressIndicator()),
    ],
    _GenerationPhase.inProgress => [
      Text(
        _inProgressText(l10n: l10n),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 24),
      const Center(child: CircularProgressIndicator()),
    ],
    _GenerationPhase.choosingCutout => [
      Text(
        l10n.generationChooseCutoutTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.generationChooseCutoutMessage,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: _useSubjectCutout,
        child: Text(l10n.generationCreateWithCutout),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () =>
            _startChoosingRange(photo: _preparedPhoto!, subjectMaskError: null),
        child: Text(l10n.generationChooseRangeMyself),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.generationRetake),
      ),
    ],
    _GenerationPhase.choosingRange => [
      Text(
        l10n.generationChooseRangeTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.generationChooseRangeMessage,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      if (_subjectMaskError != null) ...[
        const SizedBox(height: 12),
        Text(
          '${l10n.generationAutoCutoutUnavailable}\n$_subjectMaskError',
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.small,
        ),
      ],
      const SizedBox(height: 28),
      FilledButton(
        onPressed: _confirmCrop,
        child: Text(l10n.generationCreateWithRange),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.generationRetake),
      ),
    ],
    _GenerationPhase.opponentFound => [
      Text(
        l10n.generationOpponentAppeared(
          _firstBattleOpponent!.cpuOpponent.opponentName,
        ),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.generationLetsBattleWith(_firstBattleMonster!.definition.name),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 24),
      // バトルの画面を開くまでの待ち (_openFirstBattleTimer) を見せる。繰り返すアニメーションにしない
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _opponentRevealDuration,
        builder: (context, value, _) => ClipRRect(
          borderRadius: SnapmonRadii.tag,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            color: SnapmonColors.accent,
            backgroundColor: SnapmonColors.surface,
          ),
        ),
      ),
    ],
    _GenerationPhase.alreadyInDex => [
      Text(
        l10n.generationAlreadyInDexTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.generationAlreadyInDexMessage(
          _alreadyInDexMonster!.definition.name,
        ),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: () => _prepareFirstBattle(monster: _alreadyInDexMonster!),
        child: Text(l10n.generationBattleWithThisMonster),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.generationRetake),
      ),
    ],
    _GenerationPhase.waiting => [
      Text(
        l10n.generationWaitingTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.generationWaitingMessage,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: _fetchAgain,
        child: Text(l10n.generationCheckAgain),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.generationSeeLater),
      ),
    ],
    _GenerationPhase.notGenerated => [
      Text(
        l10n.generationNotBornTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        _notGeneratedText(l10n: l10n, result: _result!),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.generationRetake),
      ),
    ],
    _GenerationPhase.error => [
      Text(
        _firstBattleMonster == null
            ? l10n.generationFailedTitle
            : l10n.generationBattlePreparationFailedTitle,
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        _error.toString(),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body.copyWith(
          color: SnapmonColors.hitPointsLoss,
        ),
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: _firstBattleMonster == null
            ? _generate
            : () => _prepareFirstBattle(monster: _firstBattleMonster!),
        child: Text(l10n.commonRetry),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.commonBack),
      ),
    ],
  };

  /// 進めている手順の文言。サーバーの段階は最後に済んだ段階 ([_completedStage]) の次の手順を出す。
  String _inProgressText({required AppLocalizations l10n}) {
    if (_preparedPhoto == null) {
      return l10n.generationStagePreparingPhoto;
    }
    if (_maskSource == null) {
      return _crop == null
          ? l10n.generationStageFindingSubject
          : l10n.generationStageCroppingRange;
    }
    if (!_isUploaded) {
      return l10n.generationStageUploadingPhoto;
    }
    return switch (_completedStage) {
      null || GenerationStage.uploaded => l10n.generationStageCheckingPhoto,
      GenerationStage.safesearch => l10n.generationStageCuttingOut,
      GenerationStage.cutout => l10n.generationStageWritingName,
      GenerationStage.claude ||
      GenerationStage.classify ||
      GenerationStage.dedupe => l10n.generationStageDecidingElements,
      GenerationStage.judge ||
      GenerationStage.saved => l10n.generationStageBeingBorn,
    };
  }

  /// 生成しなかった・失敗した [result] の理由の文言。
  static String _notGeneratedText({
    required AppLocalizations l10n,
    required GenerationResult result,
  }) => switch (result.rejectionReason) {
    GenerationRejectionReason.explicitContent =>
      l10n.generationRejectedExplicitContent,
    GenerationRejectionReason.faceDetected ||
    GenerationRejectionReason.personDetected => l10n.generationRejectedPerson,
    GenerationRejectionReason.inappropriateText ||
    GenerationRejectionReason.refused => l10n.generationRejectedRefused,
    null => l10n.generationFailedMessage,
  };
}

/// 切り抜くかを選んでもらう間に、OS の切り出しで切り抜いた絵と元の写真を横に並べて見比べさせる。
class _CutoutChoicePreview extends StatelessWidget {
  const _CutoutChoicePreview({
    required this.cutoutPreview,
    required this.photo,
  });

  /// OS の切り出しのマスクで切り抜いた絵 (背景が透明な PNG)。
  final Uint8List cutoutPreview;

  /// 生成に送る写真 (切り抜く前)。
  final Uint8List photo;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _CutoutChoiceTile(
          label: context.l10n.generationCutoutLabel,
          // 切り出した絵は形を崩さず、透明な背景を地の色で見せる (生成を待つ間のプレビューと同じ)
          image: ColoredBox(
            key: const Key('cutout-choice-cutout'),
            color: SnapmonColors.artBackground,
            child: Image.memory(
              cutoutPreview,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _CutoutChoiceTile(
          label: context.l10n.generationOriginalPhotoLabel,
          image: Image.memory(
            photo,
            key: const Key('cutout-choice-photo'),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: SnapmonColors.surfaceRaised),
          ),
        ),
      ),
    ],
  );
}

/// [_CutoutChoicePreview] の 1 枚。正方形の [image] の下に [label] を出す。
class _CutoutChoiceTile extends StatelessWidget {
  const _CutoutChoiceTile({required this.label, required this.image});

  /// 絵の下に出す名前。
  final String label;

  /// 正方形の枠に収める絵。
  final Widget image;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(borderRadius: SnapmonRadii.card, child: image),
      ),
      const SizedBox(height: 8),
      Text(label, textAlign: TextAlign.center, style: SnapmonTextStyles.label),
    ],
  );
}
