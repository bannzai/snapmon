import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/square_icon_button.dart';
import '../battle/battle_recorder.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../home/home_shell.dart';
import 'cpu_party.dart';

/// 対戦相手を選ぶ画面 (モックの Pvp.dc.html)。PvP の相手の取得 (#16) までは見本の対戦相手を並べる。
class OpponentScreen extends StatelessWidget {
  /// 対戦相手の画面を作る。
  const OpponentScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.battleRecorder,
  });

  /// 見本データ (見本の対戦相手)。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  Future<void> _challenge({
    required BuildContext context,
    required SampleOpponent opponent,
  }) async {
    // 相性表は対戦時点の最新の版を使う (documents/adr/0001-tech-stack.md)。読み直せない時は古い版で戦わせず、エラーをそのまま出す
    try {
      await dexStore.refreshDefinitions();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    // 挑むたびに別の展開にするため、seed は毎回作る。値の範囲は DeterministicRandom の状態 (32 bit) に合わせた。
    // Web (JavaScript) ではシフトが 32 bit に切り詰められ `1 << 32` が 0 になるため、上限は整数リテラルで書く
    final randomSeed = math.Random().nextInt(0x100000000);
    final playerParty = dexStore.party;
    final opponentMonsters = [
      for (final monsterId in opponent.monsterIds)
        sampleData.monsterById(monsterId: monsterId),
    ];
    final action = await Navigator.of(context).push(
      MaterialPageRoute<BattleScreenAction>(
        builder: (context) => BattleScreen(
          playerParty: playerParty,
          opponentParty: opponent.id == cpuOpponentId
              ? buildCpuParty(
                  monsters: opponentMonsters,
                  playerParty: playerParty,
                  randomSeed: randomSeed,
                )
              : opponentMonsters,
          // 見本の対戦相手の属性・技は master と同じ ID・同じ値のため (test/sample/sample_data_test.dart)、
          // 図鑑の定義 (サーバーの master と図鑑が参照する定義) から両者を引ける
          definitions: dexStore.definitions,
          randomSeed: randomSeed,
          battleRecorder: battleRecorder,
          onPlayerLevelsChanged: dexStore.updateLevels,
        ),
      ),
    );
    if (action == BattleScreenAction.openDex) {
      onSelectTab(tab: HomeTab.dex);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dexStore,
    builder: (context, _) {
      final party = dexStore.party;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('対戦', style: SnapmonTextStyles.screenTitle),
                    SizedBox(height: 2),
                    Text('1 戦ごとにレベルが 1 上がる', style: SnapmonTextStyles.caption),
                  ],
                ),
              ),
              SquareIconButton(
                icon: Icons.settings_outlined,
                tooltip: '設定',
                onPressed: onOpenSettings,
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'じぶんの手持ち',
            style: SnapmonTextStyles.caption.copyWith(
              color: SnapmonColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final monster in party)
                _MonsterChip(
                  name: monster.definition.name,
                  detail: 'Lv. ${monster.level}',
                  color: SnapmonColors.card,
                  textColor: SnapmonColors.textOnCard,
                ),
              Material(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.button,
                child: InkWell(
                  borderRadius: SnapmonRadii.button,
                  onTap: () => onSelectTab(tab: HomeTab.dex),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text('入替', style: SnapmonTextStyles.caption),
                  ),
                ),
              ),
            ],
          ),
          if (party.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('手持ちを入れると挑めます', style: SnapmonTextStyles.body),
          ],
          const SizedBox(height: 20),
          const Text('相手をえらぶ', style: SnapmonTextStyles.caption),
          const SizedBox(height: 10),
          for (final opponent in sampleData.opponents) ...[
            _OpponentCard(
              opponent: opponent,
              sampleData: sampleData,
              playerParty: party,
              onChallenge: party.isEmpty
                  ? null
                  : () => _challenge(context: context, opponent: opponent),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              const Expanded(
                child: Text('相手のモンスターに問題があれば', style: SnapmonTextStyles.small),
              ),
              TextButton(
                // 通報・ブロックは #16 で実装する
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('通報とブロックは準備中です'))),
                child: Text(
                  '通報 · ブロック',
                  style: SnapmonTextStyles.small.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: SnapmonColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// 対戦相手 1 人のカード。
class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required this.opponent,
    required this.sampleData,
    required this.playerParty,
    required this.onChallenge,
  });

  final SampleOpponent opponent;
  final SampleData sampleData;

  /// 自分の手持ち。CPU の手持ちのレベルはこの平均に合わせる ([buildCpuParty])。
  final List<OwnedMonster> playerParty;

  /// 挑む。手持ちがいない時は null で、挑むボタンを押せなくする。
  final VoidCallback? onChallenge;

  @override
  Widget build(BuildContext context) {
    final monsters = [
      for (final monsterId in opponent.monsterIds)
        sampleData.monsterById(monsterId: monsterId),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SnapmonColors.surface,
        borderRadius: SnapmonRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opponent.name, style: SnapmonTextStyles.label),
                      Text(
                        opponent.id == cpuOpponentId
                            ? playerParty.isEmpty
                                  ? '手持ちのレベルに合わせる'
                                  : '平均 Lv. ${averagePartyLevel(party: playerParty)} 前後'
                            : '平均 Lv. ${averagePartyLevel(party: monsters)}',
                        style: SnapmonTextStyles.small,
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  key: Key('challenge-${opponent.id}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    shape: const RoundedRectangleBorder(
                      borderRadius: SnapmonRadii.tag,
                    ),
                    textStyle: SnapmonTextStyles.caption,
                  ),
                  onPressed: onChallenge,
                  child: const Text('挑む'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final monster in monsters)
                  _MonsterChip(
                    name: monster.definition.name,
                    detail: null,
                    color: SnapmonColors.surfaceRaised,
                    textColor: SnapmonColors.textOnBackground,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// モンスターの名前の小さな札。
class _MonsterChip extends StatelessWidget {
  const _MonsterChip({
    required this.name,
    required this.detail,
    required this.color,
    required this.textColor,
  });

  final String name;

  /// 名前の後ろに添える補足 (レベル)。無ければ null。
  final String? detail;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, borderRadius: SnapmonRadii.button),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        detail == null ? name : '$name  $detail',
        style: SnapmonTextStyles.small.copyWith(color: textColor),
      ),
    ),
  );
}
