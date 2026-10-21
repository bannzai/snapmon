import 'package:flame/game.dart';
import 'package:flutter/material.dart';

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
import 'battle_field_game.dart';

/// バトル画面を閉じた後に、呼び出し元にしてほしいこと。
enum BattleScreenAction {
  /// 図鑑のタブを開く (モンスターを交代)。
  openDex,
}

/// 1 画面に並べる技のボタンの数 (モックの Battle.dc.html の「技 4 つ」)。
const int _moveButtonCount = 4;

/// バトル画面 (モックの Battle.dc.html)。フィールドは Flame の [BattleFieldGame]、
/// 名前・HP・技のボタンは Flutter で描く。技を選んでターンを進める処理とエフェクトは #15 で足す。
class BattleScreen extends StatefulWidget {
  /// [playerParty] と [opponentParty] (それぞれ 1〜3 体) のバトル画面を作る。
  const BattleScreen({
    super.key,
    required this.playerParty,
    required this.opponentParty,
    required this.definitions,
  });

  /// 自分の手持ち。
  final List<OwnedMonster> playerParty;

  /// 相手の手持ち。
  final List<OwnedMonster> opponentParty;

  /// 属性・技の定義。
  final MasterData definitions;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final BattleState _battleState;
  late final BattleFieldGame _game;

  /// バトルの乱数の seed。ターンを進めない骨組みの間は結果に効かないため固定した。
  static const int _randomSeed = 1;

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
      randomSeed: _randomSeed,
    );
    _game = BattleFieldGame(
      playerMonster: _battleState.player.activeMember.definition,
      opponentMonster: _battleState.opponent.activeMember.definition,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerMonster = _battleState.player.activeMember;
    final opponentMonster = _battleState.opponent.activeMember;
    final moves = selectableMoves(
      monster: playerMonster,
      master: widget.definitions,
    );
    final moveSlots = [
      for (var index = 0; index < _moveButtonCount; index++)
        index < moves.length ? moves[index] : null,
    ];
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
                            '${opponentMonster.definition.name} が 勝負をしかけてきた',
                            style: SnapmonTextStyles.body,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: MediaQuery.paddingOf(context).top + 76,
                  child: _MonsterStatusCard(
                    monster: opponentMonster,
                    definitions: widget.definitions,
                    hitPointsColor: SnapmonColors.hitPointsLoss,
                    showsHitPointsNumber: false,
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
              child: Column(
                children: [
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
                  for (
                    var rowStart = 0;
                    rowStart < moveSlots.length;
                    rowStart += 2
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (column, move)
                                in moveSlots
                                    .skip(rowStart)
                                    .take(2)
                                    .indexed) ...[
                              if (column > 0) const SizedBox(width: 10),
                              Expanded(
                                child: _MoveButton(
                                  move: move,
                                  remainingPowerPoints: move == null
                                      ? 0
                                      : playerMonster
                                                .state
                                                .remainingPowerPoints[move
                                                .id] ??
                                            0,
                                  definitions: widget.definitions,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _BattleCommandButton(
                          label: 'モンスターを交代',
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(BattleScreenAction.openDex),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BattleCommandButton(
                          label: 'にげる',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          Row(
            children: [
              Expanded(
                child: Text(
                  monster.definition.name,
                  overflow: TextOverflow.ellipsis,
                  style: SnapmonTextStyles.label.copyWith(
                    color: SnapmonColors.textOnCard,
                  ),
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
            child: LinearProgressIndicator(
              value: monster.state.currentHitPoints / maximumHitPoints,
              minHeight: 8,
              color: hitPointsColor,
              backgroundColor: SnapmonColors.cardTrack,
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
    required this.move,
    required this.remainingPowerPoints,
    required this.definitions,
  });

  final Move? move;
  final int remainingPowerPoints;
  final MasterData definitions;

  @override
  Widget build(BuildContext context) {
    final move = this.move;
    return Container(
      constraints: const BoxConstraints(minHeight: _moveButtonMinimumHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: move == null ? SnapmonColors.surface : SnapmonColors.card,
        borderRadius: SnapmonRadii.card,
      ),
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
                  '${definitions.elementTypes.firstWhere((elementType) => elementType.id == move.elementTypeId).displayName}  威力 ${move.power}  PP $remainingPowerPoints/${move.powerPoints}',
                  style: SnapmonTextStyles.small.copyWith(
                    color: SnapmonColors.textOnCardMuted,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 交代・にげるのボタン。
class _BattleCommandButton extends StatelessWidget {
  const _BattleCommandButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: SnapmonColors.surface,
    borderRadius: SnapmonRadii.button,
    child: InkWell(
      borderRadius: SnapmonRadii.button,
      onTap: onPressed,
      child: SizedBox(
        height: 44,
        child: Center(child: Text(label, style: SnapmonTextStyles.caption)),
      ),
    ),
  );
}
