import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../analytics/analytics_events.dart';
import '../../audio/game_audio.dart';
import '../../domain/battle/battle_engine.dart';
import '../../domain/battle/battle_state.dart';
import '../../domain/battle/move_special_effect.dart';
import '../../domain/battle/status_condition.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../domain/monster/monster_state.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../../widgets/move_summary.dart';
import '../../widgets/trainer_icon.dart';
import '../dex/owned_monster.dart';
import '../opponent/pvp_client.dart';
import '../reference/move_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';
import '../share/share_card_button.dart';
import '../share/share_cards.dart';
import 'battle_field_game.dart';
import 'battle_haptics.dart';
import 'battle_recorder.dart';
import 'move_effect_sprite_sheets.dart';

/// バトル画面を閉じた後に、呼び出し元にしてほしいこと。
enum BattleScreenAction {
  /// 図鑑のタブを開く (モンスターを交代)。
  openDex,
}

/// 対戦の相手の種類。バトル完了の計測の `opponent` に名前 (`cpu` / `pvp`) をそのまま送る。
enum BattleOpponentKind {
  /// CPU トレーナー。
  cpu,

  /// 他のユーザーの手持ち (非同期 PvP。相手の行動は CPU の規則で決める)。本人の操作なしに他人の手持ちを CPU に操作させないため、
  /// 今はどの画面も使わない (issue #130。PvP の次の形は documents/DIRECTION.md の 2026-10-31 の行で判断待ち)。
  pvp,
}

/// 攻撃の前進の往復にかける時間。フィールドの演出 ([attackLungeSeconds]) と揃える。
const Duration _lungeDuration = Duration(
  milliseconds: (attackLungeSeconds * 2 * 1000) ~/ 1,
);

/// 被弾の点滅と HP バーの減りにかける時間。フィールドの演出 ([hitReactionSeconds]) と揃える。
const Duration _hitDuration = Duration(
  milliseconds: (hitReactionSeconds * 1000) ~/ 1,
);

/// 倒れた・交代したのログを読ませる間。ログの帯の 1 行を読める長さにした。
const Duration _messageDuration = Duration(milliseconds: 700);

/// フィールドの左右の端からログの帯・情報カードまでの間 (モックの Battle.dc.html の左右の余白)。
const double _fieldHorizontalMargin = 20;

/// セーフエリアの上端からログの帯の上端までの高さ (モックの Battle.dc.html の配置)。
const double _battleLogTop = 16;

/// セーフエリアの上端から、ログの帯の下に置く相手の情報カードの上端までの高さ (モックの Battle.dc.html の配置)。
const double _opponentStatusCardBelowLogTop = 96;

/// 情報カードの幅 (モックの Battle.dc.html の配置)。
const double _monsterStatusCardWidth = 190;

/// 自分の情報カードを相手の情報カードと同じ高さの右に並べる時に、2 枚の間に残す最小の幅。2 枚の間には 2 体の絵を並べる。
/// 120 は、相手の絵 (一辺 m) と 1.15 倍の自分の絵を横に並べ (2.15m)、m が 55 (下のセーフエリアのある横向きのスマホのフィールドの高さ 103 の約半分) になる幅にした。
/// 横向きのスマホは内容の幅の上限 600 (appContentMaxWidth) で描かれ、2 枚の間に 164 残るため並べられる
const double _monsterArtAreaMinimumWidthBetweenCards = 120;

/// トレーナーの札と情報カードの間。札がどちらのカードに付くかを近さで示しつつ、札の暗い地とカードの縁が接して見えない最小の間にした。
const double _trainerLabelGap = 6;

/// 札を一度も出していない時に見積もるトレーナーの札の高さ (アイコン 28 と上下の余白 6 ずつ)。
/// 出した後は測った高さ ([_BattleScreenState._trainerLabelPlateMeasuredHeight]) を使う
const double _trainerLabelPlateEstimatedHeight = 40;

/// フィールドの下端から自分の情報カードの下端までの高さ (モックの Battle.dc.html の配置)。
const double _playerStatusCardBottom = 24;

/// 低い画面で相手の情報カードの右に寄せたログの帯と、カードの間。
/// 縦向きのカードと帯の間 (上から 56〜96 の 40) まで空けると横向きで帯が短くなるため、詰めた値にした
const double _battleLogGapBesideCard = 8;

/// 低くて幅も狭い画面で、ログの帯と同じ高さの相手の情報カードと、その下の右下に置く自分の情報カードの間。
/// 2 枚のカードは横に重なる (幅 390 では 20 + 190 + 190 + 20 = 420 に足りない) ため、上下に空ける最小の間を、ログの帯とカードの間と揃えた
const double _stackedStatusCardGap = 8;

/// 技のボタン (と勝敗) の欄に使う画面の高さの割合の上限。
/// 0.6 は 390×844 で勝敗・カード・ボタンが全部収まり、フィールドの相手のカードが隠れない割合にした
const double _commandsPanelMaxHeightRatio = 0.6;

/// 低くて幅も狭い画面で技のボタンの欄を詰める時の、画面の高さに対する欄の高さの下限の割合。
/// 390×390 で HP の行が折り返す自分のカード (高さ 115) を相手のカードの下に積むと、欄に残るのは 390 − 249 − 32 = 109 で、
/// 0.25 (97.5) はそれを妨げない。端末の文字が大きくカードが高い時に、欄が無くなり技を選べなくなるのを防ぐ下限にした
const double _commandsPanelMinHeightRatio = 0.25;

/// 技のボタンの欄の上と下の余白 (フィールドの下端と欄の間、欄と画面の下端の間)。フィールドの高さの計算と欄の Padding の両方で使う。
const double _commandsPanelVerticalPadding = 16;

/// ログの帯をフィールドの外 (技のボタンの欄の上) に置く時の、画面の高さに対する帯の高さの上限の割合。大きい文字で超えた分は帯の中でスクロールする。
/// フィールドの下に積む配置では、技のボタン・勝敗の欄の上限 [_commandsPanelMaxHeightRatio] の半分にして、帯が伸びても欄の半分を技のボタンに残す。
/// 左右配置のバトルでは右の欄が画面の高さいっぱいで、844×390 なら帯の下に 390 − 8 × 2 − 117 − 10 = 247 (下のセーフエリア 21 では 226) が残り、
/// 見出しと技のボタン 2 行 (各 [_moveButtonMinimumHeight] 以上と行の間 10 で 148) が入る
const double _battleLogOutsideFieldMaxHeightRatio =
    _commandsPanelMaxHeightRatio / 2;

/// ログの帯をフィールドの外に置く時の、帯と技のボタン・勝敗の欄の間。
/// 欄の中の見出しと技のボタン、技のボタンの行同士の間 (10) とそろえ、帯を欄の 1 段として並べて見せる
const double _battleLogCommandsGap = 10;

/// 左右配置のバトルで、フィールドの端と情報カード、情報カードと絵の領域、フィールドの左右の端と絵の領域の間。
/// 高さ 390 のフィールドでは上下に 4 か所空くため、縦向きの余白 [_fieldHorizontalMargin] (20) にすると
/// 絵の一辺が (20 − 8) × 4 / [landscapeMonsterArtAreaHeightDivisor] ≈ 27 縮み、844×390 の相手の絵 (約 90) が約 63 になって
/// battle_screen_test.dart の下限 60 に迫る。低い画面で詰めた他の間 ([_battleLogGapBesideCard]・[_stackedStatusCardGap]) と同じ 8 にした
const double _landscapeBattleFieldGap = 8;

/// バトル画面 (モックの Battle.dc.html)。フィールドは Flame の [BattleFieldGame]、名前・HP・技のボタン・ログの帯・勝敗は Flutter で描く。
/// 技を選ぶと CPU の行動と合わせて 1 ラウンド (両陣営 1 ターンずつ) を [advanceRound] で解決し、増えたバトルのログを 1 件ずつ演出して見せる。
/// 決着がつくと勝敗と、戦闘に出た自分のモンスターのレベルの上がり方を出し、Functions に結果を記録して Analytics にバトル完了を送る。
class BattleScreen extends StatefulWidget {
  /// [playerParty] と [opponentParty] (それぞれ 1〜3 体) のバトル画面を作る。
  const BattleScreen({
    super.key,
    required this.playerParty,
    required this.opponentParty,
    required this.opponentKind,
    required this.definitions,
    required this.randomSeed,
    required this.battleRecorder,
    required this.onPlayerLevelsChanged,
    required this.cardSharer,
    required this.firstBattleBornMonster,
    required this.firstBattleMonsterIsNewlyBorn,
    required this.playerProfile,
    required this.opponentDisplayName,
  });

  /// 自分のアイコンと表示名。相手の情報カードと向かい合う自分の情報カードの上に出す。
  /// ログインが無い時 (DEBUG ビルドでログインを飛ばした時) と読めなかった時は null で、出さない (バトルは止めない)。
  final PlayerProfile? playerProfile;

  /// 相手の表示名。相手の情報カードの上に出す。相手は CPU トレーナーだけでアイコンが無く、既定の印を描く。
  final String opponentDisplayName;

  /// [firstBattleBornMonster] がこの導線で新しく生まれたか。同じ被写体でもう図鑑にいたモンスターで戦う時は false で、
  /// 勝敗の画面のカードに「あたらしい なかま」と出さない。初回の導線以外の対戦では使わない。
  final bool firstBattleMonsterIsNewlyBorn;

  /// 初回の導線 (手持ちが空の時に写真を選んでそのまま戦う 1 戦目) で生まれたモンスター。それ以外の対戦は null。
  /// null 以外の時は、技のボタンの上に技の選び方を 1 行で出し、勝敗の画面に生まれたカードと「もう 1 体撮る」「図鑑を見る」を
  /// 「もどる」の代わりに出し、決着で計測の `first_experience` (`battle_completed`) を送る。
  final OwnedMonster? firstBattleBornMonster;

  /// 自分の手持ち。
  final List<OwnedMonster> playerParty;

  /// 相手の手持ち。
  final List<OwnedMonster> opponentParty;

  /// 相手の種類 (バトル完了の計測に付ける)。
  final BattleOpponentKind opponentKind;

  /// 属性・技・エフェクトの定義。
  final MasterData definitions;

  /// バトルの乱数の seed ([startBattle])。同じ seed と同じ技の選び方からは同じ展開になる。
  final int randomSeed;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 決着の後、自分のモンスターのレベルが変わった時に monsterId ごとのレベルで呼ぶ。
  /// 記録しない対戦 (ログインが無い) では端末の計算で上がったレベルで、
  /// 記録する対戦では Functions が返したレベルで 1 回呼ぶ。記録に失敗した時は呼ばない。
  final void Function({required Map<String, int> levelsByMonsterId})
  onPlayerLevelsChanged;

  /// 勝敗の画面からバトルの結果を共有する関数の組。
  final CardSharer cardSharer;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with WidgetsBindingObserver {
  /// バトルの計算の最新の状態。演出の途中は画面に出ている状態より先に進んでいる。
  late BattleState _battleState;

  late final BattleFieldGame _game;

  /// 回転でフィールドの親が変わっても、演出中のゲームの widget を維持する。
  final GlobalKey _gameWidgetKey = GlobalKey();

  /// フィールドに重ねる相手の情報カード。高さを測り、自分のモンスターの絵がカードに隠れないようフィールドに渡す。
  final GlobalKey _opponentStatusCardKey = GlobalKey();

  /// 最後に測った相手の情報カードの高さ。フィールドの低さの判定に使う。最初のフレームを描くまでは null。
  double? _opponentStatusCardHeight;

  /// 相手のトレーナーの札。出した時に高さを測る (文字の拡大や名前の長さで見積もりの高さを超えるため)。
  final GlobalKey _opponentTrainerLabelKey = GlobalKey();

  /// 最後に札を出した時に測った札の高さ。札を出していない間は測らず前の値を使う
  /// (札を出すかの判定に使うため、出していない間に測り直すと、出すと収まらず消し、消すと収まり出す往復になる)。
  double? _trainerLabelPlateMeasuredHeight;

  /// フィールドに重ねる自分の情報カード。HP の数値と属性の札の行が折り返すと相手のカードより高くなるため、高さを測って配置の判定に使う。
  final GlobalKey _playerStatusCardKey = GlobalKey();

  /// 最後に測った自分の情報カードの高さ。最初のフレームを描くまでは null。
  double? _playerStatusCardHeight;

  /// 縦に並べた配置で、自分のトレーナーの札と情報カードを積んだ列。2 体の絵が重ならないよう矩形をフィールドに渡す。
  final GlobalKey _playerStatusCardColumnKey = GlobalKey();

  /// 技のボタン (決着の後は勝敗) の欄の中身。スクロールの中で高さの制約を受けずに描かれるため、測った高さは欄を詰める前の高さになる。
  final GlobalKey _commandsPanelContentKey = GlobalKey();

  /// 最後に測った技のボタンの欄の中身の高さ。最初のフレームを描くまでは null。
  double? _commandsPanelContentHeight;

  /// 画面に出している場のモンスター (HP は演出に合わせて減らす)。演出が終わると [_battleState] の場のモンスターに揃える。
  late Map<BattleSideId, BattleMonster> _displayedActiveMembers;

  /// ログの帯に出している文言を、画面の言語の文言から作る。initState では文言 (Localizations) を引けないため、
  /// 文言そのものではなく作り方を持つ。
  late String Function(AppLocalizations l10n) _logText;

  /// 演出を再生しているか。再生中は技・交代・にげるを押せない。
  bool _isPlaying = false;

  /// startBattle の呼び出し。決着の後に battleId を受け取って recordBattle に使う。
  late final Future<String?> _battleRecordStart;

  /// 勝敗の画面に出す、バトルの記録の状態の文言の作り方 ([_logText] と同じく画面の言語の文言から作る)。決着前は null。
  String Function(AppLocalizations l10n)? _recordStatusText;

  /// 決着の後に確定した自分のモンスターのレベル (monsterId ごと)。記録する対戦は Functions が返した値で、
  /// 記録の待ち・失敗の間は空のまま (勝敗の画面に確定していないレベルアップを出さないため)。
  Map<String, int> _appliedLevels = const {};

  /// フィールドに描くために読んだ切り出した被写体の画像。画面を閉じる時に dispose する。
  final List<ui.Image> _loadedArtImages = [];

  /// BGM・効果音。dispose でも使うため initState で引いておく (dispose では context から引けない)。
  late final GameAudio _gameAudio = GameAudioScope.read(context);

  /// 被弾・倒れる・状態の変化に合わせた触覚のフィードバック (iOS / Android だけ)。
  final BattleHaptics _haptics = BattleHaptics();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_gameAudio.playBackgroundMusic(music: BackgroundMusic.battle));
    List<BattleMonster> prepare({required List<OwnedMonster> party}) => [
      for (final monster in party)
        prepareBattleMonster(
          definition: monster.definition,
          level: monster.level,
          experience: 0,
          master: widget.definitions,
        ),
    ];
    _battleState = startBattle(
      playerMembers: prepare(party: widget.playerParty),
      opponentMembers: prepare(party: widget.opponentParty),
      randomSeed: widget.randomSeed,
      battleDate: DateTime.now(),
    );
    _displayedActiveMembers = _activeMembersOf(state: _battleState);
    final firstOpponentName =
        _battleState.opponent.activeMember.definition.name;
    _logText = (l10n) => l10n.battleLogChallenged(firstOpponentName);
    _game = BattleFieldGame(
      playerMonster: _ownedMonsterOf(
        side: BattleSideId.player,
        monsterId: _battleState.player.activeMember.definition.id,
      ),
      opponentMonster: _ownedMonsterOf(
        side: BattleSideId.opponent,
        monsterId: _battleState.opponent.activeMember.definition.id,
      ),
    );
    for (final artPath in {
      for (final monster in [...widget.playerParty, ...widget.opponentParty])
        ?monster.artPath,
    }) {
      unawaited(_loadArtImage(artPath: artPath));
    }
    // 読み込みが済むまでの被弾はパーティクルで描くため、待たずにバトルを始める。読むのはこのバトルの両陣営が使い得る技のエフェクトだけ
    unawaited(
      loadMoveEffectSpriteSheets(
        game: _game,
        effects: {
          for (final monster in [
            ...widget.playerParty,
            ...widget.opponentParty,
          ])
            for (final learnsetEntry in monster.definition.learnset)
              widget.definitions.effectById(
                effectId: widget.definitions
                    .moveById(moveId: learnsetEntry.moveId)
                    .effectId,
              ),
        },
        assetBundle: rootBundle,
      ),
    );
    _battleRecordStart = widget.battleRecorder.startBattleRecord(
      partyMonsterIds: [
        for (final monster in widget.playerParty) monster.definition.id,
      ],
    );
    // 決着の前に失敗しても、ここでは扱わず決着の後に出す (未処理の例外として報告させないため)
    _battleRecordStart.ignore();
  }

  /// 幅の上限の内側では MediaQuery が変わらないリサイズでも、元のウィンドウで配置を判定し直す。
  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final artImage in _loadedArtImages) {
      artImage.dispose();
    }
    // 閉じた先 (対戦・撮るのタブ、生まれた画面) は下タブの画面のため、その曲に戻す
    unawaited(_gameAudio.playBackgroundMusic(music: BackgroundMusic.home));
    super.dispose();
  }

  /// [side] の手持ちの [monsterId] のモンスター (切り出した被写体の画像を持つ)。
  /// 見本同士の対戦では同じ monsterId が両陣営にいるため、陣営の手持ちから引く。
  OwnedMonster _ownedMonsterOf({
    required BattleSideId side,
    required String monsterId,
  }) => switch (side) {
    BattleSideId.player => widget.playerParty,
    BattleSideId.opponent => widget.opponentParty,
  }.firstWhere((monster) => monster.definition.id == monsterId);

  /// [artPath] の切り出した被写体の画像を読み、フィールドのモンスターを画像で描くようにする。
  /// 読めない時はフィールドの仮の絵のままバトルを続ける (絵のためにバトルを止めないため)。
  Future<void> _loadArtImage({required String artPath}) async {
    try {
      final artImage = await widget.cardSharer.loadArtImage(artPath: artPath);
      if (!mounted) {
        artImage.dispose();
        return;
      }
      _loadedArtImages.add(artImage);
      _game.applyArtImage(artPath: artPath, artImage: artImage);
    } catch (error) {
      debugPrint('$artPath: $error');
    }
  }

  /// [state] の両陣営の場のモンスター。
  static Map<BattleSideId, BattleMonster> _activeMembersOf({
    required BattleState state,
  }) => {
    for (final side in BattleSideId.values)
      side: state.partyOf(side: side).activeMember,
  };

  /// [playerAction] と CPU の行動で 1 ラウンド (両陣営 1 ターンずつ) を進め、増えたログを順に演出する。決着がついたら [_finishBattle] に進む。
  Future<void> _selectAction({required BattleAction playerAction}) async {
    final previousState = _battleState;
    final nextState = advanceRound(
      state: previousState,
      playerAction: playerAction,
      opponentAction: chooseCpuAction(
        state: previousState,
        side: BattleSideId.opponent,
        master: widget.definitions,
      ),
      master: widget.definitions,
    );
    setState(() {
      _battleState = nextState;
      _isPlaying = true;
    });
    for (final event in nextState.events.skip(previousState.events.length)) {
      await _playEvent(event: event, nextState: nextState);
      if (!mounted) {
        return;
      }
    }
    setState(() {
      // 決着した状態は場の手持ちのレベルが上がった後のため写さない。場のカードに確定していないレベルを出さないため
      // (HP・交代は各ログの演出で反映済みで、確定したレベルは勝敗の画面に出す)
      if (nextState.winner == null) {
        _displayedActiveMembers = _activeMembersOf(state: nextState);
      }
      _isPlaying = false;
    });
    if (nextState.winner != null) {
      // 決着の曲は無いため BGM を止め、勝敗の効果音だけを鳴らす (画面を閉じると下タブの曲に戻る)
      unawaited(_gameAudio.stopBackgroundMusic());
      unawaited(
        _gameAudio.playSoundEffect(
          effect: nextState.winner == BattleSideId.player
              ? SoundEffect.victory
              : SoundEffect.defeat,
        ),
      );
      await _finishBattle(finishedState: nextState);
    }
  }

  /// [side] の相手の陣営。
  static BattleSideId _otherSideOf({required BattleSideId side}) =>
      switch (side) {
        BattleSideId.player => BattleSideId.opponent,
        BattleSideId.opponent => BattleSideId.player,
      };

  /// 場のモンスターの表示 ([_displayedActiveMembers]) のうち [side] の状態を [update] で置き換える。
  void _updateDisplayedMember({
    required BattleSideId side,
    required MonsterState Function(MonsterState state) update,
  }) {
    final member = _displayedActiveMembers[side]!;
    _displayedActiveMembers[side] = BattleMonster(
      definition: member.definition,
      state: update(member.state),
    );
  }

  /// バトルのログ [event] 1 件を演出する。[nextState] はこのラウンドを解決した後の状態。
  Future<void> _playEvent({
    required BattleEvent event,
    required BattleState nextState,
  }) async {
    switch (event) {
      case MoveUsedEvent():
        final attacker = _displayedActiveMembers[event.attackerSide]!;
        final defenderSide = _otherSideOf(side: event.attackerSide);
        final move = event.moveId == null
            ? null
            : widget.definitions.moveById(moveId: event.moveId!);
        final replacedMove = event.replacedMoveId == null
            ? null
            : widget.definitions.moveById(moveId: event.replacedMoveId!);
        // ログの文言は言語の切り替えで後から組み立て直すため、技を受けた側の名前はこの時点の値で固定する (交代の後に別の名前にならないように)
        final defenderName =
            _displayedActiveMembers[defenderSide]!.definition.name;
        setState(
          () => _logText = (l10n) => [
            if (replacedMove != null && move != null)
              l10n.battleLogConfusedMove(
                attacker.definition.name,
                replacedMove.displayName,
                move.displayName,
              )
            else
              l10n.battleLogMoveUsed(
                attacker.definition.name,
                move?.displayName ?? l10n.battleStruggle,
              ),
            if (event.isOneHitKnockout) l10n.battleLogOneHitKnockout,
            // 効果が働かなかった (倍率 100%) 時は、起きていないことを出さない。
            // 説明文は技の名前と同じく master の定義の文言のため、ARB には移さない
            if (event.specialEffect case (
              :final powerPercent,
              :final description,
            ) when powerPercent > 100)
              description,
            if (move?.category != MoveCategory.support &&
                !event.isOneHitKnockout &&
                event.typeMultiplier > 1)
              l10n.battleLogSuperEffective,
            if (move?.category != MoveCategory.support &&
                !event.isOneHitKnockout &&
                event.typeMultiplier < 1)
              l10n.battleLogNotVeryEffective,
            for (final change in event.statModifierChanges)
              _statModifierChangeLog(
                l10n: l10n,
                change: change,
                monsterName: change.side == event.attackerSide
                    ? attacker.definition.name
                    : defenderName,
              ),
            if (event.recoveredHitPoints > 0)
              l10n.battleLogRecovered(
                attacker.definition.name,
                event.recoveredHitPoints,
              ),
            if (event.selfDestructed)
              l10n.battleLogSelfDestructed(attacker.definition.name),
            if (move?.category == MoveCategory.support &&
                event.statModifierChanges.isEmpty &&
                event.recoveredHitPoints == 0 &&
                !_hasValueEffectToPlay(
                  nextState: nextState,
                  moveUsedEvent: event,
                ))
              l10n.battleLogNoEffect,
          ].join('\n'),
        );
        if (event.statModifierChanges.isNotEmpty) {
          unawaited(_haptics.statusChanged());
        }
        if (move?.category == MoveCategory.support) {
          // 補助技はダメージを与えないため、突進と被弾の演出をせず、HP とステータスの倍率だけを変える
          setState(() {
            for (final side in BattleSideId.values) {
              _updateDisplayedMember(
                side: side,
                update: (state) => state.copyWith(
                  currentHitPoints: side == event.attackerSide
                      ? event.attackerRemainingHitPoints
                      : null,
                  statModifierPercents: {
                    ...state.statModifierPercents,
                    for (final change in event.statModifierChanges)
                      if (change.side == side)
                        change.statKind: change.newPercent,
                  },
                ),
              );
            }
          });
          await Future<void>.delayed(_messageDuration);
          return;
        }
        _game.lunge(attackerSide: event.attackerSide);
        await Future<void>.delayed(_lungeDuration);
        if (!mounted) {
          return;
        }
        _game.hit(
          defenderSide: defenderSide,
          effect: move == null
              ? null
              : widget.definitions.effectById(effectId: move.effectId),
        );
        unawaited(_gameAudio.playSoundEffect(effect: SoundEffect.hit));
        unawaited(_haptics.hit());
        setState(() {
          _updateDisplayedMember(
            side: defenderSide,
            update: (state) => state.copyWith(
              currentHitPoints: event.defenderRemainingHitPoints,
              statModifierPercents: {
                ...state.statModifierPercents,
                for (final change in event.statModifierChanges)
                  if (change.side == defenderSide)
                    change.statKind: change.newPercent,
              },
            ),
          );
          // 攻撃技でも HP の吸収・自爆で技を使った側の HP が変わる
          _updateDisplayedMember(
            side: event.attackerSide,
            update: (state) => state.copyWith(
              currentHitPoints: event.attackerRemainingHitPoints,
              statModifierPercents: {
                ...state.statModifierPercents,
                for (final change in event.statModifierChanges)
                  if (change.side == event.attackerSide)
                    change.statKind: change.newPercent,
              },
            ),
          );
        });
        await Future<void>.delayed(_hitDuration);
      case ActionFailedEvent():
        final monsterName =
            _displayedActiveMembers[event.side]!.definition.name;
        final move = event.moveId == null
            ? null
            : widget.definitions.moveById(moveId: event.moveId!);
        setState(
          () => _logText = (l10n) => switch (event.reason) {
            ActionFailureReason.missed =>
              '${l10n.battleLogMoveUsed(monsterName, move?.displayName ?? l10n.battleStruggle)}\n${l10n.battleLogMissed}',
            ActionFailureReason.paralysis => l10n.battleLogParalyzed(
              monsterName,
            ),
            ActionFailureReason.stun => l10n.battleLogStunned(monsterName),
            ActionFailureReason.sleep => l10n.battleLogAsleep(monsterName),
            ActionFailureReason.frozen => l10n.battleLogFrozenSolid(
              monsterName,
            ),
          },
        );
        await Future<void>.delayed(_messageDuration);
      case StatusConditionInflictedEvent():
        final monsterName =
            _displayedActiveMembers[event.side]!.definition.name;
        setState(() {
          _updateDisplayedMember(
            side: event.side,
            update: (state) => state.copyWith(
              statusConditions: {
                ...state.statusConditions,
                event.kind: StatusCondition(
                  kind: event.kind,
                  remainingTurns: null,
                  stackCount: event.stackCount,
                  cursedStatKind: event.cursedStatKind,
                ),
              }..remove(event.replacedKind),
            ),
          );
          _logText = (l10n) {
            final statusName = statusConditionLabel(
              l10n: l10n,
              kind: event.kind,
            );
            if (event.replacedKind case final replacedKind?) {
              return l10n.battleLogStatusReplaced(
                monsterName,
                statusConditionLabel(l10n: l10n, kind: replacedKind),
                statusName,
              );
            }
            if (event.cursedStatKind case final cursedStatKind?) {
              return l10n.battleLogCursedStat(
                monsterName,
                statLabel(l10n: l10n, statKind: cursedStatKind),
              );
            }
            return event.stackCount > 1
                ? l10n.battleLogStatusStacked(
                    monsterName,
                    statusName,
                    event.stackCount,
                  )
                : l10n.battleLogStatusInflicted(monsterName, statusName);
          };
        });
        unawaited(_haptics.statusChanged());
        await Future<void>.delayed(_messageDuration);
      case StatusConditionCuredEvent():
        final monsterName =
            _displayedActiveMembers[event.side]!.definition.name;
        setState(() {
          _updateDisplayedMember(
            side: event.side,
            update: (state) => state.copyWith(
              statusConditions: {
                for (final MapEntry(key: kind, value: condition)
                    in state.statusConditions.entries)
                  if (!event.kinds.contains(kind)) kind: condition,
              },
            ),
          );
          _logText = (l10n) => [
            for (final kind in event.kinds)
              l10n.battleLogStatusCured(
                monsterName,
                statusConditionLabel(l10n: l10n, kind: kind),
              ),
          ].join('\n');
        });
        unawaited(_haptics.statusChanged());
        await Future<void>.delayed(_messageDuration);
      case StatusConditionDamageEvent():
        final monsterName =
            _displayedActiveMembers[event.side]!.definition.name;
        setState(() {
          _updateDisplayedMember(
            side: event.side,
            update: (state) =>
                state.copyWith(currentHitPoints: event.remainingHitPoints),
          );
          _logText = (l10n) => l10n.battleLogStatusDamage(
            monsterName,
            statusConditionLabel(l10n: l10n, kind: event.kind),
          );
        });
        unawaited(_haptics.hit());
        await Future<void>.delayed(_messageDuration);
      case FieldEffectStartedEvent():
        setState(
          () => _logText = (l10n) => switch (event.kind) {
            FieldEffectKind.statShuffle =>
              l10n.battleLogFieldStatShuffleStarted,
          },
        );
        await Future<void>.delayed(_messageDuration);
      case FieldEffectShuffledEvent():
        setState(
          () => _logText = (l10n) => l10n.battleLogFieldStatShuffled(
            statLabel(l10n: l10n, statKind: event.statKinds.$1),
            statLabel(l10n: l10n, statKind: event.statKinds.$2),
          ),
        );
        await Future<void>.delayed(_messageDuration);
      case FieldEffectEndedEvent():
        setState(() => _logText = (l10n) => l10n.battleLogFieldEnded);
        await Future<void>.delayed(_messageDuration);
      case MonsterFaintedEvent():
        final faintedName =
            _displayedActiveMembers[event.side]!.definition.name;
        setState(() {
          _logText = (l10n) => l10n.battleLogFainted(faintedName);
          _updateDisplayedMember(
            side: event.side,
            update: (state) => state.copyWith(currentHitPoints: 0),
          );
        });
        _game.faint(side: event.side);
        unawaited(_gameAudio.playSoundEffect(effect: SoundEffect.faint));
        unawaited(_haptics.faint());
        await Future<void>.delayed(_messageDuration);
      case MonsterSwitchedInEvent():
        final member = nextState
            .partyOf(side: event.side)
            .members
            .firstWhere((member) => member.definition.id == event.monsterId);
        setState(() {
          _displayedActiveMembers[event.side] = member;
          _logText = (l10n) => l10n.battleLogSwitchedIn(member.definition.name);
        });
        _game.switchIn(
          side: event.side,
          monster: _ownedMonsterOf(
            side: event.side,
            monsterId: event.monsterId,
          ),
        );
        await Future<void>.delayed(_messageDuration);
      case LevelUpEvent():
      case BattleFinishedEvent():
        // レベルアップと勝敗は勝敗の画面にまとめて出す
        break;
    }
  }

  /// 補助技のログ [moveUsedEvent] の直後に、その技の値の効果 (状態・解除・フィールド) のログが続くか。
  /// 続くなら「しかし なにも おこらなかった」を出さない (起きたことが次のログに出るため)。
  static bool _hasValueEffectToPlay({
    required BattleState nextState,
    required MoveUsedEvent moveUsedEvent,
  }) {
    final eventIndex = nextState.events.indexOf(moveUsedEvent);
    final nextEvent = nextState.events.elementAtOrNull(eventIndex + 1);
    return nextEvent is StatusConditionInflictedEvent ||
        nextEvent is StatusConditionCuredEvent ||
        nextEvent is FieldEffectStartedEvent;
  }

  /// ステータスの倍率の変化 [change] (変わったモンスターの名前 [monsterName]) のログの 1 行。
  static String _statModifierChangeLog({
    required AppLocalizations l10n,
    required StatModifierChange change,
    required String monsterName,
  }) {
    final statName = statLabel(l10n: l10n, statKind: change.statKind);
    return change.newPercent > change.previousPercent
        ? l10n.battleLogStatRose(monsterName, statName)
        : change.newPercent < change.previousPercent
        ? l10n.battleLogStatFell(monsterName, statName)
        : l10n.battleLogStatUnchanged(monsterName, statName);
  }

  /// 決着した [finishedState] の結果を反映する:バトル完了を Analytics に送り、Functions に結果を記録し、
  /// 自分のモンスターのレベルを呼び出し元に渡す ([BattleScreen.onPlayerLevelsChanged])。記録の成否は勝敗の画面に出す。
  Future<void> _finishBattle({required BattleState finishedState}) async {
    final finishedEvent = finishedState.events
        .whereType<BattleFinishedEvent>()
        .single;
    final playerLevelUps = _playerLevelUpsOf(state: finishedState);
    setState(() => _recordStatusText = (l10n) => l10n.battleRecording);
    unawaited(
      widget.battleRecorder
          .logEvent(
            event: AnalyticsEvent.battleCompleted,
            parameters: {
              'result': finishedEvent.winner == BattleSideId.player
                  ? 'win'
                  : 'lose',
              'turn_count': finishedEvent.turnNumber,
              'opponent': widget.opponentKind.name,
            },
          )
          // 計測の失敗はバトルの記録と画面に影響させない (未処理の非同期の例外として報告させないため)
          .catchError((Object _) {}),
    );
    if (widget.firstBattleBornMonster != null) {
      unawaited(
        widget.battleRecorder
            .logEvent(
              event: AnalyticsEvent.firstExperience,
              parameters: {
                'step': FirstExperienceStep.battleCompleted.stepName,
              },
            )
            .catchError((Object _) {}),
      );
    }
    try {
      final battleId = await _battleRecordStart;
      if (battleId == null) {
        // 記録しない対戦は端末の計算のレベルを反映する。記録する対戦は Functions が成功した時だけ反映し、
        // 拒否された (1 日の上限等) 時にサーバーと食い違うレベルを残さない
        _applyPlayerLevels(
          levelsByMonsterId: {
            for (final levelUp in playerLevelUps)
              levelUp.monsterId: levelUp.newLevel,
          },
        );
        if (mounted) {
          setState(() => _recordStatusText = (l10n) => l10n.battleNotRecorded);
        }
        return;
      }
      final recordedLevels = await widget.battleRecorder.completeBattleRecord(
        battleId: battleId,
        participantMonsterIds: [
          for (final levelUp in playerLevelUps) levelUp.monsterId,
        ],
        winner: finishedEvent.winner,
        turnCount: finishedEvent.turnNumber,
      );
      _applyPlayerLevels(levelsByMonsterId: recordedLevels);
      if (mounted) {
        setState(() => _recordStatusText = (l10n) => l10n.battleRecorded);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _recordStatusText = (_) => error.toString());
      }
    }
  }

  /// 確定したレベル [levelsByMonsterId] を呼び出し元に渡し、勝敗の画面に出す。
  void _applyPlayerLevels({required Map<String, int> levelsByMonsterId}) {
    widget.onPlayerLevelsChanged(levelsByMonsterId: levelsByMonsterId);
    if (mounted) {
      setState(() => _appliedLevels = levelsByMonsterId);
    }
  }

  /// [state] のログのうち、自分の陣営のレベルアップ (戦闘に出た自分のモンスター)。
  static List<LevelUpEvent> _playerLevelUpsOf({required BattleState state}) => [
    for (final levelUp in state.events.whereType<LevelUpEvent>())
      if (levelUp.side == BattleSideId.player) levelUp,
  ];

  @override
  Widget build(BuildContext context) {
    final playerMonster = _displayedActiveMembers[BattleSideId.player]!;
    final opponentMonster = _displayedActiveMembers[BattleSideId.opponent]!;
    final isFinished = _battleState.winner != null && !_isPlaying;
    final safeAreaPadding = MediaQuery.paddingOf(context);
    final safeAreaTop = safeAreaPadding.top;
    // 文字の拡大率が変わるとカードの高さも変わるため、拡大率の変更でも build し直してカードを測り直す
    MediaQuery.textScalerOf(context);
    // 端のスワイプ (iOS) と戻るボタン・戻るジェスチャー (Android) でバトルを抜けると、決着の前に手が触れただけで閉じるため、
    // 閉じるのは「にげる」「モンスターを交代」・勝敗の画面のボタンだけにする。ボタンの Navigator.pop は PopScope で止まらない。
    // pop を拒む route は端のスワイプも受け付けない (Flutter の ModalRoute.popGestureEnabled が popDisposition の doNotPop で false を返す)
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, bodyConstraints) {
            // 初回の 1 戦は生まれたカードも並べて高さが増え、技のボタンは名前・属性の札と数値・効果の説明の 3 段で大きい文字では段が折り返すため、
            // 低い画面・大きい文字でもフィールドを残してスクロールさせる
            final commandsPanelNaturalMaxHeight =
                MediaQuery.sizeOf(context).height *
                _commandsPanelMaxHeightRatio;
            // 配置の種類は、技のボタンの欄を詰める前のフィールドの高さで決める
            // (詰めて高くなったフィールドで決め直すと、ログの帯の下に相手のカードを戻して右下の自分のカードと重なるため)。
            // 欄の中身を測る前は、中身が上限まであると見積もる。
            // ログの帯をフィールドの下に出す時は欄がその分高く、フィールドは見積もりより低くなるが、帯を下に出すのは低い画面と決めた後だけのため、決め直しても変わらない
            final naturalFieldHeight =
                bodyConstraints.maxHeight -
                math.min(
                  _commandsPanelContentHeight ?? commandsPanelNaturalMaxHeight,
                  commandsPanelNaturalMaxHeight,
                ) -
                2 * _commandsPanelVerticalPadding -
                safeAreaPadding.bottom;
            // 自分のカードは測るまで相手のカードと同じ高さと見積もる
            final playerStatusCardHeight =
                _playerStatusCardHeight ?? _opponentStatusCardHeight;
            final safeAreaInnerWidth =
                bodyConstraints.maxWidth - safeAreaPadding.horizontal;
            // 幅の狭い画面では、左の相手のカードと右下の自分のカードが横に重なる (幅 390 では 20 + 190 + 190 + 20 = 420 に足りない)
            final statusCardsOverlapHorizontally =
                safeAreaInnerWidth <
                _fieldHorizontalMargin * 2 + _monsterStatusCardWidth * 2;
            // ログの帯の下 (上から 96) に置くとカードがフィールドの下にはみ出す低い画面 (横向きのスマホ) では、
            // 相手のカードをログの帯と同じ高さの左に上げ、自分のカードも帯と同じ高さの右に上げる。
            // 844×390 の実測でフィールドは 124 (下のセーフエリアのある実機は約 103)、ログの帯は上から 16〜56、カードは 86 で、
            // ログの帯の下には収まらず、帯と同じ高さ (16 + 86 = 102) なら収まるため。
            // 2 枚のカードが横に重なる幅では、右下の自分のカードまでログの帯の下の相手のカードの下に収まらない時も低い画面とする
            // (自分のカードは HP の数値と属性の札の行が折り返すと高さ 115 になり、390×560 ではログの帯の下の相手のカードと重なっていた)。
            // 自分のカードを相手のカードと同じ高さの右に並べるのは、セーフエリアの内側の幅に 2 枚のカードと 2 枚の間の最小の幅が入る時だけにする
            // (低くて幅も狭い画面で並べると、2 枚のカードが重なるため。その時は右下に置き、下の技のボタンの欄を詰める)。
            // 並べた時は、2 枚の間 (164 × 86) に 2 体の絵を置き、ログの帯をフィールドの下 (技のボタンの上) に出す。
            // 帯を 2 枚の間に残すと、絵の置き場が無く (絵が大きさの下限 18.6 に縮んでカードの下に隠れていた)、
            // 幅 164 の帯は技の特殊効果の説明が付くと 4 行を越えて高さ 103 のフィールドの下で切れていたため
            final isFieldTooLowForCardBelowLog =
                _opponentStatusCardHeight != null &&
                safeAreaTop +
                        _opponentStatusCardBelowLogTop +
                        _opponentStatusCardHeight! +
                        (statusCardsOverlapHorizontally
                            ? _stackedStatusCardGap +
                                  playerStatusCardHeight! +
                                  _playerStatusCardBottom
                            : 0) >
                    naturalFieldHeight;
            final placesPlayerStatusCardBesideOpponentCard =
                isFieldTooLowForCardBelowLog &&
                safeAreaInnerWidth >=
                    _fieldHorizontalMargin * 2 +
                        _monsterStatusCardWidth * 2 +
                        _battleLogGapBesideCard * 2 +
                        _monsterArtAreaMinimumWidthBetweenCards;
            // トレーナーの札は、ログの帯の下に相手の札とカード、フィールドの下に自分の札とカードを積んでも、
            // 上下の 2 組が重ならない高さのフィールドの時だけ出す (自分のカードは測った高さを使う。HP の数値と属性の札の行が折り返すと相手より高いため)。
            // 低い画面 (横向きのスマホ・小さい Web のウィンドウ) は、カードだけでもフィールドにやっと収まり、
            // 札を積んでも横に並べても札やカードがフィールドの外で切れるかログの帯と重なるため、札を出さずにカードとログを優先する
            final trainerLabelPlateHeight =
                _trainerLabelPlateMeasuredHeight ??
                _trainerLabelPlateEstimatedHeight;
            final showsTrainerLabels =
                _opponentStatusCardHeight != null &&
                safeAreaTop +
                        _opponentStatusCardBelowLogTop +
                        trainerLabelPlateHeight +
                        _trainerLabelGap +
                        _opponentStatusCardHeight! +
                        trainerLabelPlateHeight +
                        _trainerLabelGap +
                        playerStatusCardHeight! +
                        _playerStatusCardBottom <=
                    naturalFieldHeight;
            final opponentStatusCardTop =
                safeAreaTop +
                (isFieldTooLowForCardBelowLog
                    ? _battleLogTop
                    : _opponentStatusCardBelowLogTop) +
                (showsTrainerLabels
                    ? trainerLabelPlateHeight + _trainerLabelGap
                    : 0);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              if (_opponentStatusCardKey.currentContext?.size?.height
                  case final cardHeight?
                  when cardHeight != _opponentStatusCardHeight) {
                setState(() => _opponentStatusCardHeight = cardHeight);
              }
              // 自分のカードは高くなった時だけ測り直す。HP の桁が減って行の折り返しが消えるとカードが低くなり、
              // 境界の高さでは配置がバトルの途中で切り替わるため、判定には一度測った一番高い値を使う
              if (_playerStatusCardKey.currentContext?.size?.height
                  case final cardHeight?
                  when cardHeight > (_playerStatusCardHeight ?? 0)) {
                setState(() => _playerStatusCardHeight = cardHeight);
              }
              // 技のボタンの欄 (決着の後は勝敗の画面) も、高くなった時だけ測り直す。
              // 欄が低くなる時 (技の説明の行数が少ないモンスターに交代した等) に測り直すと配置がバトルの途中で切り替わり、
              // 高くなる時 (わるあがきの行が増えた・勝敗の画面に変わった) に測り直さないと、縮んだフィールドの上で札とカードが重なるため
              if (_commandsPanelContentKey.currentContext?.size?.height
                  case final contentHeight?
                  when contentHeight > (_commandsPanelContentHeight ?? 0)) {
                setState(() => _commandsPanelContentHeight = contentHeight);
              }
              if (_opponentTrainerLabelKey.currentContext?.size?.height
                  case final labelHeight?
                  when labelHeight != _trainerLabelPlateMeasuredHeight) {
                setState(() => _trainerLabelPlateMeasuredHeight = labelHeight);
              }
            });
            // 短辺 600 以上はタブレット、長辺 1000 以上は広いウィンドウとして従来の配置を残す。
            // 内容幅が 600 に制限されても区別できるよう元のウィンドウを見て、
            // 実際の使用可能な幅が 560 (各欄 280) 未満なら、狭い画面の既存の配置に戻す。
            final windowSize = MediaQueryData.fromView(View.of(context)).size;
            if (windowSize.shortestSide < 600 &&
                windowSize.longestSide < 1000 &&
                safeAreaInnerWidth >= 560 &&
                safeAreaInnerWidth >
                    bodyConstraints.maxHeight - safeAreaPadding.vertical) {
              return _buildLandscapeBattle(
                context: context,
                playerMonster: playerMonster,
                opponentMonster: opponentMonster,
                isFinished: isFinished,
              );
            }
            return Column(
              children: [
                Expanded(
                  // 絵の置き場をフィールドの実際の高さで抑えるため、フィールドの大きさをここで受け取る
                  child: LayoutBuilder(
                    builder: (context, fieldConstraints) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        if (_opponentStatusCardKey.currentContext?.size?.height
                            case final cardHeight?) {
                          _game
                            // 2 体の絵が情報カードとトレーナーの札に重ならないよう、重ねた部品の矩形を渡す (#243)
                            ..updateOverlayRects(
                              rects: [
                                for (final overlayKey in [
                                  _opponentTrainerLabelKey,
                                  _opponentStatusCardKey,
                                  _playerStatusCardColumnKey,
                                ])
                                  ?_rectInField(widgetKey: overlayKey),
                              ],
                            )
                            // 2 枚のカードの間を、カードと同じ高さの範囲で絵に使う (自分のカードも相手のカードと同じ高さの 3 段に保つため)
                            ..updateMonsterArtArea(
                              area: placesPlayerStatusCardBesideOpponentCard
                                  ? Rect.fromLTRB(
                                      safeAreaPadding.left +
                                          _fieldHorizontalMargin +
                                          _monsterStatusCardWidth +
                                          _battleLogGapBesideCard,
                                      opponentStatusCardTop,
                                      fieldConstraints.maxWidth -
                                          safeAreaPadding.right -
                                          _fieldHorizontalMargin -
                                          _monsterStatusCardWidth -
                                          _battleLogGapBesideCard,
                                      // 下のパネルが高くフィールドがカードより低い時も、絵がフィールドの外で切れないようにフィールドの高さで抑える
                                      math.min(
                                        opponentStatusCardTop + cardHeight,
                                        fieldConstraints.maxHeight,
                                      ),
                                    )
                                  : null,
                            );
                        }
                      });
                      return _buildField(
                        playerMonster: playerMonster,
                        opponentMonster: opponentMonster,
                        safeAreaLeft: safeAreaPadding.left,
                        safeAreaRight: safeAreaPadding.right,
                        opponentStatusCardTop: opponentStatusCardTop,
                        placesOpponentStatusCardBesideLog:
                            isFieldTooLowForCardBelowLog,
                        placesPlayerStatusCardBesideOpponentCard:
                            placesPlayerStatusCardBesideOpponentCard,
                        showsTrainerLabels: showsTrainerLabels,
                        trainerLabelPlateHeight: trainerLabelPlateHeight,
                        // 低くて幅も狭い画面では、相手のカードの右に寄せたログの帯が右下の自分のカードと横に重なるため、
                        // 帯の高さを自分のカードの上端の手前までにして、技の特殊効果の説明が付いて伸びた時は帯の中をスクロールさせる
                        battleLogMaxHeight:
                            isFieldTooLowForCardBelowLog &&
                                !placesPlayerStatusCardBesideOpponentCard
                            ? math.max(
                                0.0,
                                fieldConstraints.maxHeight -
                                    _playerStatusCardBottom -
                                    playerStatusCardHeight! -
                                    _stackedStatusCardGap -
                                    safeAreaTop -
                                    _battleLogTop,
                              )
                            : null,
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      _commandsPanelVerticalPadding,
                      20,
                      _commandsPanelVerticalPadding,
                    ),
                    // ログの帯をフィールドの下に置く時は、帯を技のボタンの欄の上限の中のスクロールの外に置く
                    // (スクロールの中に置くと、下の技を押すためにスクロールした時に帯が隠れるため。上限を変えないのはフィールドを低くしないため)
                    child: ConstrainedBox(
                      // 低くて幅も狭い画面 (390×390 のような小さい Web のウィンドウ) は、2 枚のカードを横にも縦にも重ねずに置くには
                      // フィールドが足りないため、技のボタンの欄を詰め、相手のカードの下に自分のカードを置ける高さをフィールドに残す (欄はスクロールする)
                      constraints: BoxConstraints(
                        maxHeight:
                            isFieldTooLowForCardBelowLog &&
                                !placesPlayerStatusCardBesideOpponentCard
                            ? math.max(
                                MediaQuery.sizeOf(context).height *
                                    _commandsPanelMinHeightRatio,
                                math.min(
                                  commandsPanelNaturalMaxHeight,
                                  bodyConstraints.maxHeight -
                                      (safeAreaTop +
                                          _battleLogTop +
                                          _opponentStatusCardHeight! +
                                          _stackedStatusCardGap +
                                          playerStatusCardHeight! +
                                          _playerStatusCardBottom) -
                                      2 * _commandsPanelVerticalPadding -
                                      safeAreaPadding.bottom,
                                ),
                              )
                            : commandsPanelNaturalMaxHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (placesPlayerStatusCardBesideOpponentCard) ...[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height *
                                    _battleLogOutsideFieldMaxHeightRatio,
                              ),
                              child: SingleChildScrollView(
                                child: _buildBattleLog(context: context),
                              ),
                            ),
                            const SizedBox(height: _battleLogCommandsGap),
                          ],
                          Flexible(
                            child: SingleChildScrollView(
                              child: KeyedSubtree(
                                key: _commandsPanelContentKey,
                                child: _buildCommandsOrResult(
                                  context: context,
                                  playerMonster: playerMonster,
                                  isFinished: isFinished,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// [widgetKey] の widget の矩形を、フィールド (Flame のゲームの widget) の座標で返す。
  /// widget を出していない (札を出さない画面等) か、まだ描いていない時は null。
  Rect? _rectInField({required GlobalKey widgetKey}) {
    final widgetBox = widgetKey.currentContext?.findRenderObject();
    final fieldBox = _gameWidgetKey.currentContext?.findRenderObject();
    if (widgetBox is! RenderBox ||
        fieldBox is! RenderBox ||
        !widgetBox.hasSize ||
        !fieldBox.hasSize) {
      return null;
    }
    // 位置の差分ではなく変形で直す。Android・Web の既定の画面遷移は拡大縮小を伴い、遷移の途中に測ると差分だけが縮尺倍になるため
    return MatrixUtils.transformRect(
      widgetBox.getTransformTo(fieldBox),
      Offset.zero & widgetBox.size,
    );
  }

  /// 横向きスマホのフィールドと操作。カードの文字が大きい時はフィールドもスクロールし、絵とカードを重ねない。
  Widget _buildLandscapeBattle({
    required BuildContext context,
    required BattleMonster playerMonster,
    required BattleMonster opponentMonster,
    required bool isFinished,
  }) => SafeArea(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // カードの高さは描いた後にしか測れないため、測る前の最初のフレームだけ 0 とする。
              // build の測定 (addPostFrameCallback) が測った高さを setState し、次のフレームで絵の領域を置き直す
              final opponentCardHeight = _opponentStatusCardHeight ?? 0;
              final playerCardHeight = _playerStatusCardHeight ?? 0;
              // 120 は絵の領域の高さの下限で、相手の絵を約 68px (120 / landscapeMonsterArtAreaHeightDivisor)、
              // 自分を約 79px (その 1.15 倍) より小さくしないための高さ。
              // 大きい文字でカードが伸びてもこの帯を残し、スクロールで両方のカードを読めるようにする。
              final fieldHeight = math.max(
                constraints.maxHeight,
                opponentCardHeight +
                    playerCardHeight +
                    120 +
                    _landscapeBattleFieldGap * 4,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _game.updateMonsterArtArea(
                  area: Rect.fromLTRB(
                    _landscapeBattleFieldGap,
                    opponentCardHeight + _landscapeBattleFieldGap * 2,
                    constraints.maxWidth - _landscapeBattleFieldGap,
                    fieldHeight -
                        playerCardHeight -
                        _landscapeBattleFieldGap * 2,
                  ),
                  placesPlayerOnLeft: true,
                );
              });
              return SingleChildScrollView(
                key: const Key('battle-landscape-field-scroll'),
                child: SizedBox(
                  height: fieldHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GameWidget(key: _gameWidgetKey, game: _game),
                      ),
                      Positioned(
                        top: _landscapeBattleFieldGap,
                        right: _landscapeBattleFieldGap,
                        child: _MonsterStatusCard(
                          key: _opponentStatusCardKey,
                          monster: opponentMonster,
                          definitions: widget.definitions,
                          hitPointsColor: SnapmonColors.hitPointsLoss,
                          showsHitPointsNumber: false,
                          keepsEachRowOnOneLine: false,
                        ),
                      ),
                      Positioned(
                        bottom: _landscapeBattleFieldGap,
                        left: _landscapeBattleFieldGap,
                        child: _MonsterStatusCard(
                          key: _playerStatusCardKey,
                          monster: playerMonster,
                          definitions: widget.definitions,
                          hitPointsColor: SnapmonColors.accent,
                          showsHitPointsNumber: true,
                          keepsEachRowOnOneLine: false,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Padding(
            // 600px の内容幅を半分ずつ使い、ボタンの内側の余白と合わせて文字の幅を残す。
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.sizeOf(context).height *
                        _battleLogOutsideFieldMaxHeightRatio,
                  ),
                  child: SingleChildScrollView(
                    key: const Key('battle-landscape-log-scroll'),
                    child: _buildBattleLog(context: context),
                  ),
                ),
                const SizedBox(height: _battleLogCommandsGap),
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('battle-landscape-commands-scroll'),
                    child: _buildCommandsOrResult(
                      context: context,
                      playerMonster: playerMonster,
                      isFinished: isFinished,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// 決着前は技の選択、決着後は既存の勝敗・共有・初回バトルの案内を返す。
  Widget _buildCommandsOrResult({
    required BuildContext context,
    required BattleMonster playerMonster,
    required bool isFinished,
  }) => isFinished
      ? _BattleResultPanel(
          winner: _battleState.winner!,
          appliedLevels: _appliedLevels,
          playerParty: widget.playerParty,
          recordStatusText: _recordStatusText?.call(context.l10n),
          opponentParty: widget.opponentParty,
          definitions: widget.definitions,
          cardSharer: widget.cardSharer,
          firstBattleBornMonster: widget.firstBattleBornMonster,
          firstBattleMonsterIsNewlyBorn: widget.firstBattleMonsterIsNewlyBorn,
        )
      : _buildCommands(context: context, playerMonster: playerMonster);

  /// ログの帯 (今のログの文言を出す暗い地の帯)。幅は親の幅いっぱいにする。
  Widget _buildBattleLog({required BuildContext context}) => DecoratedBox(
    decoration: const BoxDecoration(
      color: SnapmonColors.scrim,
      borderRadius: SnapmonRadii.button,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          _logText(context.l10n),
          key: const Key('battle-log'),
          style: SnapmonTextStyles.body,
        ),
      ),
    ),
  );

  /// フィールド (Flame のゲーム) と、その上に重ねるログの帯 ([placesPlayerStatusCardBesideOpponentCard] の時は重ねずフィールドの下に出す)・2 体の情報カード。
  /// 相手の情報カードの上端を [opponentStatusCardTop] に置く。
  /// [placesOpponentStatusCardBesideLog] が true の時はログの帯の左端を相手の情報カードの右に寄せ、
  /// [placesPlayerStatusCardBesideOpponentCard] が true の時は自分の情報カードを相手の情報カードと同じ高さの右に置く。false の時は右下に置く。
  /// 情報カードとトレーナーの札は、ログの帯 (SafeArea の内側) と同じく左右のセーフエリア ([safeAreaLeft]・[safeAreaRight]) の内側に置く。
  /// [showsTrainerLabels] の時は、相手と自分のトレーナーの札をそれぞれのカードの上に出す (相手の札の高さは [trainerLabelPlateHeight] と見積もる)。
  /// [battleLogMaxHeight] が null 以外の時は、フィールドに重ねるログの帯をその高さまでにし、越えた分は帯の中をスクロールさせる。
  Widget _buildField({
    required BattleMonster playerMonster,
    required BattleMonster opponentMonster,
    required double safeAreaLeft,
    required double safeAreaRight,
    required double opponentStatusCardTop,
    required bool placesOpponentStatusCardBesideLog,
    required bool placesPlayerStatusCardBesideOpponentCard,
    required bool showsTrainerLabels,
    required double trainerLabelPlateHeight,
    required double? battleLogMaxHeight,
  }) => Stack(
    children: [
      Positioned.fill(
        child: GameWidget(key: _gameWidgetKey, game: _game),
      ),
      if (!placesPlayerStatusCardBesideOpponentCard)
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              placesOpponentStatusCardBesideLog
                  ? _fieldHorizontalMargin +
                        _monsterStatusCardWidth +
                        _battleLogGapBesideCard
                  : _fieldHorizontalMargin,
              _battleLogTop,
              _fieldHorizontalMargin,
              0,
            ),
            child: battleLogMaxHeight == null
                ? _buildBattleLog(context: context)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: battleLogMaxHeight),
                    child: SingleChildScrollView(
                      child: _buildBattleLog(context: context),
                    ),
                  ),
          ),
        ),
      if (showsTrainerLabels)
        Positioned(
          left: _fieldHorizontalMargin + safeAreaLeft,
          top:
              opponentStatusCardTop -
              trainerLabelPlateHeight -
              _trainerLabelGap,
          child: KeyedSubtree(
            key: _opponentTrainerLabelKey,
            child: _TrainerLabelPlate(
              key: const Key('battle-opponent-trainer'),
              displayName: widget.opponentDisplayName,
              iconPath: null,
            ),
          ),
        ),
      Positioned(
        left: _fieldHorizontalMargin + safeAreaLeft,
        top: opponentStatusCardTop,
        child: _MonsterStatusCard(
          key: _opponentStatusCardKey,
          monster: opponentMonster,
          definitions: widget.definitions,
          hitPointsColor: SnapmonColors.hitPointsLoss,
          showsHitPointsNumber: false,
          keepsEachRowOnOneLine: false,
        ),
      ),
      Positioned(
        right: _fieldHorizontalMargin + safeAreaRight,
        top: placesPlayerStatusCardBesideOpponentCard
            ? opponentStatusCardTop
            : null,
        bottom: placesPlayerStatusCardBesideOpponentCard
            ? null
            : _playerStatusCardBottom,
        child: Column(
          key: _playerStatusCardColumnKey,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.playerProfile case final playerProfile?
                when showsTrainerLabels) ...[
              _TrainerLabelPlate(
                key: const Key('battle-player-trainer'),
                displayName: playerProfile.displayName,
                iconPath: playerProfile.iconPath,
              ),
              const SizedBox(height: _trainerLabelGap),
            ],
            _MonsterStatusCard(
              key: _playerStatusCardKey,
              monster: playerMonster,
              definitions: widget.definitions,
              hitPointsColor: SnapmonColors.accent,
              showsHitPointsNumber: true,
              keepsEachRowOnOneLine: placesPlayerStatusCardBesideOpponentCard,
            ),
          ],
        ),
      ),
    ],
  );

  /// 技のボタンと、交代・にげるのボタン。
  Widget _buildCommands({
    required BuildContext context,
    required BattleMonster playerMonster,
  }) {
    final moves = selectableMoves(
      monster: playerMonster,
      master: widget.definitions,
    );
    // 技のボタンは同時に使える技の数だけ並べる (モックの Battle.dc.html の「技 4 つ」)
    final moveSlots = [
      for (var index = 0; index < maximumEquippedMoveCount; index++)
        index < moves.length ? moves[index] : null,
    ];
    final canStruggle = !moves.any(isOrdinaryAttackMove);
    return Column(
      children: [
        if (widget.firstBattleBornMonster != null) ...[
          Text(
            context.l10n.battleFirstHint,
            key: const Key('first-battle-hint'),
            style: SnapmonTextStyles.small,
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.battleChooseMove(playerMonster.definition.name),
                style: SnapmonTextStyles.caption.copyWith(
                  color: SnapmonColors.accent,
                ),
              ),
            ),
            Text(
              context.l10n.battleTurn(_battleState.turnNumber),
              style: SnapmonTextStyles.caption,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 2 列に並べ、端末の文字を大きくした時は行ごとに高さを伸ばす (同じ行の 2 つは高さを揃える)
        for (var rowStart = 0; rowStart < moveSlots.length; rowStart += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (column, move)
                      in moveSlots.skip(rowStart).take(2).indexed) ...[
                    if (column > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _MoveButton(
                        key: Key('move-slot-${rowStart + column}'),
                        move: move,
                        remainingPowerPoints: move == null
                            ? 0
                            : playerMonster.state.remainingPowerPoints[move
                                      .id] ??
                                  0,
                        definitions: widget.definitions,
                        onPressed: move == null || _isPlaying
                            ? null
                            : () => _selectAction(
                                playerAction: UseMoveAction(moveId: move.id),
                              ),
                        // 詳細は読むだけでバトルを進めないため、演出の再生中も開ける
                        onLongPress: move == null
                            ? null
                            : () => openMoveDetail(
                                context: context,
                                move: move,
                                definitions: widget.definitions,
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (canStruggle)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BattleCommandButton(
              label: context.l10n.battleStruggle,
              onPressed: _isPlaying
                  ? null
                  : () => _selectAction(playerAction: const StruggleAction()),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _BattleCommandButton(
                label: context.l10n.battleSwitchMonster,
                onPressed: _isPlaying
                    ? null
                    : () =>
                          Navigator.of(context).pop(BattleScreenAction.openDex),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BattleCommandButton(
                label: context.l10n.battleRun,
                onPressed: _isPlaying
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 勝敗の画面。勝ち負けと、戦闘に出た自分のモンスターのレベルの上がり方、バトルの記録の状態を出す。
class _BattleResultPanel extends StatelessWidget {
  const _BattleResultPanel({
    required this.winner,
    required this.appliedLevels,
    required this.playerParty,
    required this.recordStatusText,
    required this.opponentParty,
    required this.definitions,
    required this.cardSharer,
    required this.firstBattleBornMonster,
    required this.firstBattleMonsterIsNewlyBorn,
  });

  final BattleSideId winner;

  /// 初回の 1 戦で生まれたモンスター ([BattleScreen.firstBattleBornMonster])。それ以外の対戦は null。
  final OwnedMonster? firstBattleBornMonster;

  /// [BattleScreen.firstBattleMonsterIsNewlyBorn]。
  final bool firstBattleMonsterIsNewlyBorn;

  /// 確定した自分のモンスターのレベル (monsterId ごと)。確定していない間は空。
  final Map<String, int> appliedLevels;

  /// バトルの前の自分の手持ち (上がる前のレベルを出すため)。
  final List<OwnedMonster> playerParty;

  /// バトルの記録の状態の文言。記録を始める前は null。
  final String? recordStatusText;

  /// 相手の手持ち (共有するカードに名前を出す)。
  final List<OwnedMonster> opponentParty;

  /// 属性・技の定義。
  final MasterData definitions;

  /// バトルの結果の共有に使う関数の組。
  final CardSharer cardSharer;

  @override
  Widget build(BuildContext context) {
    final bornMonster = firstBattleBornMonster;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bornMonster != null) ...[
          _BornMonsterCard(
            monster: bornMonster,
            isNewlyBorn: firstBattleMonsterIsNewlyBorn,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          winner == BattleSideId.player
              ? context.l10n.battleWon
              : context.l10n.battleLost,
          style: SnapmonTextStyles.screenTitle.copyWith(
            color: winner == BattleSideId.player
                ? SnapmonColors.accent
                : SnapmonColors.hitPointsLoss,
          ),
        ),
        // レベルが確定するまで (記録の待ち・失敗) は、上がったと読める説明を出さない
        if (appliedLevels.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.battleLevelUpNote,
            style: SnapmonTextStyles.caption,
          ),
        ],
        const SizedBox(height: 12),
        for (final monster in playerParty)
          if (appliedLevels[monster.definition.id] case final newLevel?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: SnapmonColors.card,
                  borderRadius: SnapmonRadii.button,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    '${monster.definition.name}  ${context.l10n.commonLevelUp(monster.level, newLevel)}',
                    style: SnapmonTextStyles.label.copyWith(
                      color: SnapmonColors.textOnCard,
                    ),
                  ),
                ),
              ),
            ),
        if (recordStatusText != null) ...[
          const SizedBox(height: 4),
          Text(
            recordStatusText!,
            key: const Key('battle-record-status'),
            style: SnapmonTextStyles.small,
          ),
        ],
        const SizedBox(height: 12),
        ShareCardButton(
          cardSharer: cardSharer,
          screen: ShareScreen.battleResult,
          artPaths: [for (final monster in playerParty) ?monster.artPath],
          buildCard: ({required format, required artImagesByPath}) =>
              BattleResultShareCard(
                winner: winner,
                playerParty: playerParty,
                appliedLevels: appliedLevels,
                opponentParty: opponentParty,
                artImagesByPath: artImagesByPath,
                definitions: definitions,
                format: format,
              ),
          shareText: winner == BattleSideId.player
              ? context.l10n.battleShareTextWon(landingPageUri.toString())
              : context.l10n.battleShareTextLost(landingPageUri.toString()),
          fileNamePrefix: 'snapmon-battle',
          buttonBuilder: ({required onPressed}) => _BattleCommandButton(
            label: context.l10n.battleShareResult,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 10),
        if (bornMonster == null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonBack),
          )
        else
          Row(
            children: [
              Expanded(
                child: _BattleCommandButton(
                  label: context.l10n.battleOpenDex,
                  onPressed: () =>
                      Navigator.of(context).pop(BattleScreenAction.openDex),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('first-battle-capture-again'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.resultCaptureAnother),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 初回の 1 戦の勝敗の画面に出す、生まれたモンスターのカード (名前・図鑑の文章)。
class _BornMonsterCard extends StatelessWidget {
  const _BornMonsterCard({required this.monster, required this.isNewlyBorn});

  final OwnedMonster monster;

  /// [monster] がこの導線で新しく生まれたか ([BattleScreen.firstBattleMonsterIsNewlyBorn])。
  final bool isNewlyBorn;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: SnapmonColors.card,
      borderRadius: SnapmonRadii.card,
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 72,
            child: ClipRRect(
              borderRadius: SnapmonRadii.button,
              child: MonsterArt(
                monster: monster,
                backgroundColor: SnapmonColors.cardSubtle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNewlyBorn
                      ? context.l10n.resultNewlyBorn
                      : context.l10n.battleYourMonster,
                  style: SnapmonTextStyles.small.copyWith(
                    color: SnapmonColors.textOnCardMuted,
                  ),
                ),
                Text(
                  monster.definition.name,
                  style: SnapmonTextStyles.label.copyWith(
                    color: SnapmonColors.textOnCard,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  monster.definition.encyclopediaText,
                  style: SnapmonTextStyles.small.copyWith(
                    color: SnapmonColors.textOnCardBody,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// フィールドの上に重ねるトレーナーの札 ([TrainerLabel])。フィールドの絵の上でも読めるよう、ログの帯と同じ暗い地に置く。
class _TrainerLabelPlate extends StatelessWidget {
  const _TrainerLabelPlate({
    required super.key,
    required this.displayName,
    required this.iconPath,
  });

  /// 札に出すトレーナーの表示名。
  final String displayName;

  /// 札に出すトレーナーのアイコンの Storage のパス。登録していない時は null。
  final String? iconPath;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: SnapmonColors.scrim,
      borderRadius: SnapmonRadii.button,
    ),
    child: Padding(
      // 上下と左の 6: アイコンを札の縁から少し離す最小の余白 (札の高さの見積もり _trainerLabelPlateEstimatedHeight の前提)。
      // 右の 12: 名前の文字の終わりを札の角丸 (SnapmonRadii.button) の内側に収めるため、左より広くした
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      // 名前が長くても画面の半分を超えて相手と自分の札が重ならないよう、幅を画面の半分までにする
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width / 2,
        ),
        child: TrainerLabel(displayName: displayName, iconPath: iconPath),
      ),
    ),
  );
}

/// 場のモンスターの名前・レベル・HP・属性のカード。
class _MonsterStatusCard extends StatelessWidget {
  const _MonsterStatusCard({
    super.key,
    required this.monster,
    required this.definitions,
    required this.hitPointsColor,
    required this.showsHitPointsNumber,
    required this.keepsEachRowOnOneLine,
  });

  final BattleMonster monster;
  final MasterData definitions;
  final Color hitPointsColor;

  /// HP の数値を出すか (自分のモンスターだけ出す)。
  final bool showsHitPointsNumber;

  /// 名前とレベルの行、HP の数値と属性の札の行をそれぞれ折り返さずに 1 行に収めるか
  /// (名前は省略記号で切り、HP の数値と属性の札は縮める)。
  /// 低い画面ではカードを 3 段の高さに保たないとフィールドに収まらないため、その時だけ true にする。
  final bool keepsEachRowOnOneLine;

  @override
  Widget build(BuildContext context) {
    final maximumHitPoints = calculateStats(
      baseStats: monster.definition.baseStats,
      individualValues: monster.definition.individualValues,
      level: monster.state.level,
      statCalculationVersion: monster.definition.statCalculationVersion,
    ).hitPoints;
    return Container(
      width: _monsterStatusCardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: SnapmonColors.card,
        borderRadius: SnapmonRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameAndLevel(context: context),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: SnapmonRadii.tag,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                end: monster.state.currentHitPoints / maximumHitPoints,
              ),
              // 被弾の演出と同じ時間で減らす
              duration: _hitDuration,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: hitPointsColor,
                backgroundColor: SnapmonColors.cardTrack,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildHitPointsAndElementTypes(
            context: context,
            maximumHitPoints: maximumHitPoints,
          ),
        ],
      ),
    );
  }

  /// 名前とレベルの行。
  Widget _buildNameAndLevel({required BuildContext context}) {
    final nameText = Text(
      monster.definition.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SnapmonTextStyles.label.copyWith(color: SnapmonColors.textOnCard),
    );
    final levelText = Text(
      context.l10n.commonLevel(monster.state.level),
      style: SnapmonTextStyles.small.copyWith(
        color: SnapmonColors.textOnCardMuted,
      ),
    );
    if (keepsEachRowOnOneLine) {
      // 名前が長い時は名前を省略記号で切り、レベルを同じ行に残す
      return Row(
        spacing: 8,
        children: [
          Flexible(child: nameText),
          levelText,
        ],
      );
    }
    // 名前とレベルが 1 行に収まらない時 (端末の文字が大きい時) はレベルを次の行に回す
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [nameText, levelText],
    );
  }

  /// HP の数値 ([showsHitPointsNumber] の時) と属性の札の行。最大 HP を [maximumHitPoints] で受け取る。
  Widget _buildHitPointsAndElementTypes({
    required BuildContext context,
    required int maximumHitPoints,
  }) {
    final children = [
      if (showsHitPointsNumber)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            context.l10n.battleHitPoints(
              monster.state.currentHitPoints,
              maximumHitPoints,
            ),
            style: SnapmonTextStyles.small.copyWith(
              color: SnapmonColors.textOnCardMuted,
            ),
          ),
        ),
      for (final elementTypeId in monster.definition.elementTypeIds)
        ElementTypeTag(elementTypeId: elementTypeId, definitions: definitions),
      // 補助技で変わったステータスの倍率 (等倍のステータスは出さない)
      for (final statKind in modifiableStatKinds)
        if (statModifierPercentOf(monster: monster, statKind: statKind)
            case final percent when percent != 100)
          Text(
            context.l10n.battleStatModifier(
              statLabel(l10n: context.l10n, statKind: statKind),
              formatPowerPercent(powerPercent: percent),
            ),
            key: Key('battle-stat-modifier-${statKind.name}'),
            style: SnapmonTextStyles.small.copyWith(
              color: percent > 100
                  ? SnapmonColors.accent
                  : SnapmonColors.textOnCardMuted,
            ),
          ),
      // 付いている状態 (重なる状態は重なりの数も)
      for (final condition in monster.state.statusConditions.values)
        Text(
          condition.stackCount > 1
              ? context.l10n.battleStatusStackCount(
                  statusConditionLabel(
                    l10n: context.l10n,
                    kind: condition.kind,
                  ),
                  condition.stackCount,
                )
              : statusConditionLabel(l10n: context.l10n, kind: condition.kind),
          key: Key('battle-status-condition-${condition.kind.name}'),
          style: SnapmonTextStyles.small.copyWith(color: SnapmonColors.accent),
        ),
    ];
    if (keepsEachRowOnOneLine) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: children,
          ),
        ),
      );
    }
    // HP の数値と属性の札が 1 行に収まらない時は札を次の行に回す
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// 技のボタンの高さ。モック (Battle.dc.html) の技のボタンの高さから取った。端末の文字を大きくした時はこれより伸びる。
const double _moveButtonMinimumHeight = 64;

/// 技のボタン。技が無い枠 ([move] が null) は空の枠として描く。
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    super.key,
    required this.move,
    required this.remainingPowerPoints,
    required this.definitions,
    required this.onPressed,
    required this.onLongPress,
  });

  final Move? move;
  final int remainingPowerPoints;
  final MasterData definitions;

  /// 技を選ぶ。技が無い枠と演出の再生中は null で、押せなくする。
  final VoidCallback? onPressed;

  /// 長押しで技の詳細を開く。技が無い枠は null。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final move = this.move;
    return Material(
      color: move == null ? SnapmonColors.surface : SnapmonColors.card,
      borderRadius: SnapmonRadii.card,
      child: InkWell(
        borderRadius: SnapmonRadii.card,
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: _moveButtonMinimumHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: move == null
              ? const Center(child: Text('—', style: SnapmonTextStyles.caption))
              : Align(
                  alignment: Alignment.centerLeft,
                  child: MoveSummary(
                    move: move,
                    remainingPowerPoints: remainingPowerPoints,
                    definitions: definitions,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 交代・にげる・わるあがきのボタン。
class _BattleCommandButton extends StatelessWidget {
  const _BattleCommandButton({required this.label, required this.onPressed});

  final String label;

  /// 押した時の処理。演出の再生中は null で、押せなくする。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: SnapmonColors.surface,
    borderRadius: SnapmonRadii.button,
    child: InkWell(
      borderRadius: SnapmonRadii.button,
      onTap: onPressed,
      // 端末の文字を大きくした時は 44 より高く伸ばし、文字が切れないようにする
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: SnapmonTextStyles.caption,
            ),
          ),
        ),
      ),
    ),
  );
}
