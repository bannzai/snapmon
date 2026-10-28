import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../analytics/analytics_events.dart';
import '../../domain/battle/battle_engine.dart';
import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';
import '../share/share_card_button.dart';
import '../share/share_cards.dart';
import 'battle_field_game.dart';
import 'battle_recorder.dart';

/// バトル画面を閉じた後に、呼び出し元にしてほしいこと。
enum BattleScreenAction {
  /// 図鑑のタブを開く (モンスターを交代)。
  openDex,
}

/// 対戦の相手の種類。バトル完了の計測の `opponent` に名前 (`cpu` / `pvp`) をそのまま送る。
enum BattleOpponentKind {
  /// CPU トレーナー。
  cpu,

  /// 他のユーザーの手持ち (非同期 PvP。相手の行動は CPU の規則で決める)。
  pvp,
}

/// 1 画面に並べる技のボタンの数 (モックの Battle.dc.html の「技 4 つ」)。
const int _moveButtonCount = 4;

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

/// バトルの記録 (Functions) の状態を勝敗の画面に出す文言。
const String _recordingText = '記録しています';
const String _recordedText = '記録しました';
const String _notRecordedText = 'ログインしていないため記録していません';

/// バトル画面 (モックの Battle.dc.html)。フィールドは Flame の [BattleFieldGame]、名前・HP・技のボタン・ログの帯・勝敗は Flutter で描く。
/// 技を選ぶと CPU の行動と合わせて 1 ターンを [advanceTurn] で解決し、増えたバトルのログを 1 件ずつ演出して見せる。
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
    required this.opponentSafetyMenu,
  });

  /// [firstBattleBornMonster] がこの導線で新しく生まれたか。同じ被写体でもう図鑑にいたモンスターで戦う時は false で、
  /// 勝敗の画面のカードに「あたらしい なかま」と出さない。初回の導線以外の対戦では使わない。
  final bool firstBattleMonsterIsNewlyBorn;

  /// 相手の通報・ブロックのメニュー (OpponentSafetyMenuButton)。相手のカードの横に、戦っている間も決着の後も出す。
  /// 初回の導線の PvP だけが渡す (対戦相手の画面から挑む PvP は、挑む前の相手のカードで通報・ブロックできるため null)。
  final Widget? opponentSafetyMenu;

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

class _BattleScreenState extends State<BattleScreen> {
  /// バトルの計算の最新の状態。演出の途中は画面に出ている状態より先に進んでいる。
  late BattleState _battleState;

  late final BattleFieldGame _game;

  /// 画面に出している場のモンスター (HP は演出に合わせて減らす)。演出が終わると [_battleState] の場のモンスターに揃える。
  late Map<BattleSideId, BattleMonster> _displayedActiveMembers;

  /// ログの帯に出している文言。
  late String _logText;

  /// 演出を再生しているか。再生中は技・交代・にげるを押せない。
  bool _isPlaying = false;

  /// startBattle の呼び出し。決着の後に battleId を受け取って recordBattle に使う。
  late final Future<String?> _battleRecordStart;

  /// 勝敗の画面に出す、バトルの記録の状態の文言。決着前は null。
  String? _recordStatusText;

  /// 決着の後に確定した自分のモンスターのレベル (monsterId ごと)。記録する対戦は Functions が返した値で、
  /// 記録の待ち・失敗の間は空のまま (勝敗の画面に確定していないレベルアップを出さないため)。
  Map<String, int> _appliedLevels = const {};

  /// フィールドに描くために読んだ切り出した被写体の画像。画面を閉じる時に dispose する。
  final List<ui.Image> _loadedArtImages = [];

  @override
  void initState() {
    super.initState();
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
    );
    _displayedActiveMembers = _activeMembersOf(state: _battleState);
    _logText =
        '${_battleState.opponent.activeMember.definition.name} が 勝負をしかけてきた';
    _game = BattleFieldGame(
      playerMonster: _battleState.player.activeMember.definition,
      playerArtPath: _artPathOf(
        side: BattleSideId.player,
        monsterId: _battleState.player.activeMember.definition.id,
      ),
      opponentMonster: _battleState.opponent.activeMember.definition,
      opponentArtPath: _artPathOf(
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
    _battleRecordStart = widget.battleRecorder.startBattleRecord(
      partyMonsterIds: [
        for (final monster in widget.playerParty) monster.definition.id,
      ],
    );
    // 決着の前に失敗しても、ここでは扱わず決着の後に出す (未処理の例外として報告させないため)
    _battleRecordStart.ignore();
  }

  @override
  void dispose() {
    for (final artImage in _loadedArtImages) {
      artImage.dispose();
    }
    super.dispose();
  }

  /// [side] の手持ちの [monsterId] の切り出した被写体の画像のパス ([OwnedMonster.artPath])。
  /// 見本同士の対戦では同じ monsterId が両陣営にいるため、陣営の手持ちから引く。
  String? _artPathOf({required BattleSideId side, required String monsterId}) =>
      switch (side) {
        BattleSideId.player => widget.playerParty,
        BattleSideId.opponent => widget.opponentParty,
      }.firstWhere((monster) => monster.definition.id == monsterId).artPath;

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

  /// [playerAction] と CPU の行動で 1 ターンを進め、増えたログを順に演出する。決着がついたら [_finishBattle] に進む。
  Future<void> _selectAction({required BattleAction playerAction}) async {
    final previousState = _battleState;
    final nextState = advanceTurn(
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
      await _finishBattle(finishedState: nextState);
    }
  }

  /// バトルのログ [event] 1 件を演出する。[nextState] はこのターンを解決した後の状態。
  Future<void> _playEvent({
    required BattleEvent event,
    required BattleState nextState,
  }) async {
    switch (event) {
      case MoveUsedEvent():
        final attacker = _displayedActiveMembers[event.attackerSide]!;
        final defenderSide = switch (event.attackerSide) {
          BattleSideId.player => BattleSideId.opponent,
          BattleSideId.opponent => BattleSideId.player,
        };
        final move = event.moveId == null
            ? null
            : widget.definitions.moveById(moveId: event.moveId!);
        setState(
          () => _logText = [
            '${attacker.definition.name} の ${move?.displayName ?? 'わるあがき'}',
            if (event.typeMultiplier > 1) 'こうかは ばつぐんだ',
            if (event.typeMultiplier < 1) 'こうかは いまひとつ',
          ].join('\n'),
        );
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
        final defender = _displayedActiveMembers[defenderSide]!;
        setState(
          () => _displayedActiveMembers[defenderSide] = BattleMonster(
            definition: defender.definition,
            state: defender.state.copyWith(
              currentHitPoints: event.defenderRemainingHitPoints,
            ),
          ),
        );
        await Future<void>.delayed(_hitDuration);
      case MonsterFaintedEvent():
        setState(
          () => _logText =
              '${_displayedActiveMembers[event.side]!.definition.name} は たおれた',
        );
        _game.faint(side: event.side);
        await Future<void>.delayed(_messageDuration);
      case MonsterSwitchedInEvent():
        final member = nextState
            .partyOf(side: event.side)
            .members
            .firstWhere((member) => member.definition.id == event.monsterId);
        setState(() {
          _displayedActiveMembers[event.side] = member;
          _logText = '${member.definition.name} が でてきた';
        });
        _game.switchIn(
          side: event.side,
          definition: member.definition,
          artPath: _artPathOf(side: event.side, monsterId: event.monsterId),
        );
        await Future<void>.delayed(_messageDuration);
      case LevelUpEvent():
      case BattleFinishedEvent():
        // レベルアップと勝敗は勝敗の画面にまとめて出す
        break;
    }
  }

  /// 決着した [finishedState] の結果を反映する: バトル完了を Analytics に送り、Functions に結果を記録し、
  /// 自分のモンスターのレベルを呼び出し元に渡す ([BattleScreen.onPlayerLevelsChanged])。記録の成否は勝敗の画面に出す。
  Future<void> _finishBattle({required BattleState finishedState}) async {
    final finishedEvent = finishedState.events
        .whereType<BattleFinishedEvent>()
        .single;
    final playerLevelUps = _playerLevelUpsOf(state: finishedState);
    setState(() => _recordStatusText = _recordingText);
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
          setState(() => _recordStatusText = _notRecordedText);
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
        setState(() => _recordStatusText = _recordedText);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _recordStatusText = error.toString());
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
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: GameWidget(game: _game)),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: SnapmonColors.scrim,
                        borderRadius: SnapmonRadii.button,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            _logText,
                            key: const Key('battle-log'),
                            style: SnapmonTextStyles.body,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: MediaQuery.paddingOf(context).top + 96,
                  child: _MonsterStatusCard(
                    monster: opponentMonster,
                    definitions: widget.definitions,
                    hitPointsColor: SnapmonColors.hitPointsLoss,
                    showsHitPointsNumber: false,
                  ),
                ),
                if (widget.opponentSafetyMenu case final opponentSafetyMenu?)
                  Positioned(
                    right: 20,
                    top: MediaQuery.paddingOf(context).top + 96,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: SnapmonColors.scrim,
                        borderRadius: SnapmonRadii.button,
                      ),
                      child: opponentSafetyMenu,
                    ),
                  ),
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: _MonsterStatusCard(
                    monster: playerMonster,
                    definitions: widget.definitions,
                    hitPointsColor: SnapmonColors.accent,
                    showsHitPointsNumber: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: isFinished
                  // 初回の 1 戦は生まれたカードも並べて高さが増えるため、低い画面・大きい文字でもフィールドを残してスクロールさせる。
                  // 0.6 は 390×844 で勝敗・カード・ボタンが全部収まり、フィールドの相手のカードが隠れない割合にした
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                      ),
                      child: SingleChildScrollView(
                        child: _BattleResultPanel(
                          winner: _battleState.winner!,
                          appliedLevels: _appliedLevels,
                          playerParty: widget.playerParty,
                          recordStatusText: _recordStatusText,
                          opponentParty: widget.opponentParty,
                          definitions: widget.definitions,
                          cardSharer: widget.cardSharer,
                          firstBattleBornMonster: widget.firstBattleBornMonster,
                          firstBattleMonsterIsNewlyBorn:
                              widget.firstBattleMonsterIsNewlyBorn,
                        ),
                      ),
                    )
                  : _buildCommands(
                      context: context,
                      playerMonster: playerMonster,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 技のボタンと、交代・にげるのボタン。
  Widget _buildCommands({
    required BuildContext context,
    required BattleMonster playerMonster,
  }) {
    final moves = selectableMoves(
      monster: playerMonster,
      master: widget.definitions,
    );
    final moveSlots = [
      for (var index = 0; index < _moveButtonCount; index++)
        index < moves.length ? moves[index] : null,
    ];
    final canStruggle = !moves.any(
      (move) => move.category == MoveCategory.attack,
    );
    return Column(
      children: [
        if (widget.firstBattleBornMonster != null) ...[
          const Text(
            '技を選ぶと素早い方から行動する  相性のいい属性ほど大きく効く',
            key: Key('first-battle-hint'),
            style: SnapmonTextStyles.small,
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                '${playerMonster.definition.name} の 技をえらぶ',
                style: SnapmonTextStyles.caption.copyWith(
                  color: SnapmonColors.accent,
                ),
              ),
            ),
            Text(
              'ターン ${_battleState.turnNumber}',
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
              label: 'わるあがき',
              onPressed: _isPlaying
                  ? null
                  : () => _selectAction(playerAction: const StruggleAction()),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _BattleCommandButton(
                label: 'モンスターを交代',
                onPressed: _isPlaying
                    ? null
                    : () =>
                          Navigator.of(context).pop(BattleScreenAction.openDex),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BattleCommandButton(
                label: 'にげる',
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
          winner == BattleSideId.player ? 'かった' : 'まけた',
          style: SnapmonTextStyles.screenTitle.copyWith(
            color: winner == BattleSideId.player
                ? SnapmonColors.accent
                : SnapmonColors.hitPointsLoss,
          ),
        ),
        // レベルが確定するまで (記録の待ち・失敗) は、上がったと読める説明を出さない
        if (appliedLevels.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            '勝ち負けに関係なく 戦ったモンスターのレベルが上がる',
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
                    '${monster.definition.name}  Lv. ${monster.level} → $newLevel',
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
          shareText:
              '${winner == BattleSideId.player ? 'snapmon のバトルにかった' : 'snapmon のバトルにまけた'}\n#snapmon\n$landingPageUri',
          fileNamePrefix: 'snapmon-battle',
          buttonBuilder: ({required onPressed}) =>
              _BattleCommandButton(label: '結果を共有', onPressed: onPressed),
        ),
        const SizedBox(height: 10),
        if (bornMonster == null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('もどる'),
          )
        else
          Row(
            children: [
              Expanded(
                child: _BattleCommandButton(
                  label: '図鑑を見る',
                  onPressed: () =>
                      Navigator.of(context).pop(BattleScreenAction.openDex),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('first-battle-capture-again'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('もう 1 体撮る'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 初回の 1 戦の勝敗の画面に出す、生まれたモンスターのカード (名前・図鑑の文章・AI の生成であることの表示)。
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
                  isNewlyBorn ? 'あたらしい なかま' : 'きみの なかま',
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
                const SizedBox(height: 4),
                // 名前と図鑑の文章が AI の生成であることの表示 (DIRECTION.md「必要な機能」の未成年向けの安全策)
                Text(
                  '名前と図鑑の文章は AI が作りました',
                  style: SnapmonTextStyles.small.copyWith(
                    color: SnapmonColors.textOnCardMuted,
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

/// 場のモンスターの名前・レベル・HP・属性のカード。
class _MonsterStatusCard extends StatelessWidget {
  const _MonsterStatusCard({
    required this.monster,
    required this.definitions,
    required this.hitPointsColor,
    required this.showsHitPointsNumber,
  });

  final BattleMonster monster;
  final MasterData definitions;
  final Color hitPointsColor;

  /// HP の数値を出すか (自分のモンスターだけ出す)。
  final bool showsHitPointsNumber;

  @override
  Widget build(BuildContext context) {
    final maximumHitPoints = calculateStats(
      baseStats: monster.definition.baseStats,
      individualValues: monster.definition.individualValues,
      level: monster.state.level,
      statCalculationVersion: monster.definition.statCalculationVersion,
    ).hitPoints;
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: SnapmonColors.card,
        borderRadius: SnapmonRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名前とレベルが 1 行に収まらない時 (端末の文字が大きい時) はレベルを次の行に回す
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                monster.definition.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SnapmonTextStyles.label.copyWith(
                  color: SnapmonColors.textOnCard,
                ),
              ),
              Text(
                'Lv. ${monster.state.level}',
                style: SnapmonTextStyles.small.copyWith(
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
            ],
          ),
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
          // HP の数値と属性の札が 1 行に収まらない時は札を次の行に回す
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showsHitPointsNumber)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    'HP ${monster.state.currentHitPoints} / $maximumHitPoints',
                    style: SnapmonTextStyles.small.copyWith(
                      color: SnapmonColors.textOnCardMuted,
                    ),
                  ),
                ),
              for (final elementTypeId in monster.definition.elementTypeIds)
                ElementTypeTag(
                  elementTypeId: elementTypeId,
                  definitions: definitions,
                ),
            ],
          ),
        ],
      ),
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
  });

  final Move? move;
  final int remainingPowerPoints;
  final MasterData definitions;

  /// 技を選ぶ。技が無い枠と演出の再生中は null で、押せなくする。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final move = this.move;
    return Material(
      color: move == null ? SnapmonColors.surface : SnapmonColors.card,
      borderRadius: SnapmonRadii.card,
      child: InkWell(
        borderRadius: SnapmonRadii.card,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: _moveButtonMinimumHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: move == null
              ? const Center(child: Text('—', style: SnapmonTextStyles.caption))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      move.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SnapmonTextStyles.label.copyWith(
                        color: SnapmonColors.textOnCard,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      '${definitions.elementTypes.firstWhere((elementType) => elementType.id == move.elementTypeId, orElse: () => throw StateError('属性 ${move.elementTypeId} が定義に無い')).displayName}  威力 ${move.power}  PP $remainingPowerPoints/${move.powerPoints}',
                      style: SnapmonTextStyles.small.copyWith(
                        color: SnapmonColors.textOnCardMuted,
                      ),
                    ),
                  ],
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
