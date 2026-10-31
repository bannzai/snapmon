import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/master/master_data.dart';
import '../../l10n/l10n.dart';
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
import '../share/card_sharer.dart';
import 'battle_definitions.dart';
import 'cpu_party.dart';
import 'pvp_client.dart';

/// 対戦相手を選ぶ画面 (モックの Pvp.dc.html)。見本データの CPU トレーナーを先頭から [_opponentSlotCount] 人並べ、自分の戦績を出す。
/// 他のユーザーの手持ち (Functions の fetchOpponents) は相手に出さない (本人の操作なしに他人の手持ちを CPU に操作させないため。issue #130)。
class OpponentScreen extends StatefulWidget {
  /// 対戦相手の画面を作る。
  const OpponentScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.battleRecorder,
    required this.pvpClient,
    required this.cardSharer,
  });

  /// 見本データ (CPU トレーナー)。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 戦績の読み込み。
  final PvpClient pvpClient;

  /// バトルの結果の共有に使う関数の組。
  final CardSharer cardSharer;

  @override
  State<OpponentScreen> createState() => _OpponentScreenState();
}

/// 対戦相手の画面に並べる相手の数。issue #105 の「常に 3 人出す」(documents/DIRECTION.md の 2026-10-29 の #105 の行) のまま変えない。
const int _opponentSlotCount = 3;

class _OpponentScreenState extends State<OpponentScreen> {
  /// 挑む準備 (定義の読み直し) から対戦の画面を閉じるまでの間か。間は挑む操作を受け付けない
  /// (連打で対戦の画面とバトルの記録が重なるため)。
  bool _isChallenging = false;

  /// 自分の戦績 (勝ち数と負け数)。読み込み中・ログインが無い時は null。
  ({int wins, int losses})? _battleRecord;

  /// 戦績の読み込みの失敗。
  Object? _battleRecordError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBattleRecord());
  }

  /// 自分の戦績を読む。
  Future<void> _loadBattleRecord() async {
    try {
      final battleRecord = await widget.pvpClient.fetchBattleRecord();
      if (mounted) {
        setState(() {
          _battleRecord = battleRecord;
          _battleRecordError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _battleRecordError = error);
      }
    }
  }

  void _showMessage({required String message}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// CPU トレーナー [cpuTrainer] に挑む。挑んでいる間に呼ばれた時は何もしない。
  Future<void> _challenge({required SampleOpponent cpuTrainer}) async {
    if (_isChallenging) {
      return;
    }
    setState(() => _isChallenging = true);
    try {
      await _prepareAndStartBattle(cpuTrainer: cpuTrainer);
    } finally {
      if (mounted) {
        setState(() => _isChallenging = false);
      }
    }
  }

  /// 定義を読み直してから CPU トレーナー [cpuTrainer] との対戦の画面を開き、閉じるまで待つ。
  Future<void> _prepareAndStartBattle({
    required SampleOpponent cpuTrainer,
  }) async {
    final dexStore = widget.dexStore;
    final MasterData definitions;
    // 読み直せない時はエラーをそのまま出す
    try {
      definitions = await prepareBattleDefinitions(
        dexStore: dexStore,
        pvpClient: widget.pvpClient,
        pvpOpponentMonsters: null,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(message: error.toString());
      }
      return;
    }
    if (!mounted) {
      return;
    }
    // 挑むたびに別の展開にするため、seed は毎回作る。値の範囲は DeterministicRandom の状態 (32 bit) に合わせた。
    // Web (JavaScript) ではシフトが 32 bit に切り詰められ `1 << 32` が 0 になるため、上限は整数リテラルで書く
    final randomSeed = math.Random().nextInt(0x100000000);
    final playerParty = dexStore.party;
    final action = await Navigator.of(context).push(
      MaterialPageRoute<BattleScreenAction>(
        builder: (context) => BattleScreen(
          playerParty: playerParty,
          opponentParty: buildCpuParty(
            monsters: [
              for (final monsterId in cpuTrainer.monsterIds)
                widget.sampleData.monsterById(monsterId: monsterId),
            ],
            playerParty: playerParty,
          ),
          opponentKind: BattleOpponentKind.cpu,
          definitions: definitions,
          randomSeed: randomSeed,
          battleRecorder: widget.battleRecorder,
          onPlayerLevelsChanged: dexStore.updateLevels,
          cardSharer: widget.cardSharer,
          firstBattleBornMonster: null,
          firstBattleMonsterIsNewlyBorn: false,
        ),
      ),
    );
    unawaited(_loadBattleRecord());
    if (action == BattleScreenAction.openDex) {
      widget.onSelectTab(tab: HomeTab.dex);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dexStore,
    builder: (context, _) {
      final party = widget.dexStore.party;
      final canChallenge = party.isNotEmpty && !_isChallenging;
      final battleRecord = _battleRecord;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tabOpponent,
                      style: SnapmonTextStyles.screenTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.opponentLevelUpNote,
                      style: SnapmonTextStyles.caption,
                    ),
                  ],
                ),
              ),
              SquareIconButton(
                icon: Icons.settings_outlined,
                tooltip: context.l10n.settingsTitle,
                onPressed: widget.onOpenSettings,
                size: 44,
              ),
            ],
          ),
          if (battleRecord != null || _battleRecordError != null) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.card,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      context.l10n.opponentBattleRecordLabel,
                      style: SnapmonTextStyles.caption,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        battleRecord == null
                            ? _battleRecordError.toString()
                            : context.l10n.opponentBattleRecord(
                                battleRecord.wins,
                                battleRecord.losses,
                              ),
                        key: const Key('battle-record'),
                        style: battleRecord == null
                            ? SnapmonTextStyles.small
                            : SnapmonTextStyles.label,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            context.l10n.opponentMyParty,
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
                  key: null,
                  name: monster.definition.name,
                  detail: context.l10n.commonLevel(monster.level),
                  color: SnapmonColors.card,
                  textColor: SnapmonColors.textOnCard,
                ),
              Material(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.button,
                child: InkWell(
                  borderRadius: SnapmonRadii.button,
                  onTap: () => widget.onSelectTab(tab: HomeTab.dex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      context.l10n.opponentSwapParty,
                      style: SnapmonTextStyles.caption,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (party.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.opponentEmptyPartyNote,
              style: SnapmonTextStyles.body,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            context.l10n.opponentChooseOpponent,
            style: SnapmonTextStyles.caption,
          ),
          const SizedBox(height: 10),
          for (final cpuTrainer in widget.sampleData.cpuTrainers.take(
            _opponentSlotCount,
          )) ...[
            _OpponentCard(
              key: Key('opponent-card-${cpuTrainer.id}'),
              opponentId: cpuTrainer.id,
              title: cpuTrainer.name,
              subtitle: party.isEmpty
                  ? context.l10n.opponentCpuMatchesPartyLevel
                  : context.l10n.commonLevel(averagePartyLevel(party: party)),
              monsters: [
                for (final monsterId in cpuTrainer.monsterIds)
                  widget.sampleData.monsterById(monsterId: monsterId),
              ],
              onChallenge: canChallenge
                  ? () => _challenge(cpuTrainer: cpuTrainer)
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    },
  );
}

/// 対戦相手 1 人のカード (CPU トレーナー)。
class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required super.key,
    required this.opponentId,
    required this.title,
    required this.subtitle,
    required this.monsters,
    required this.onChallenge,
  });

  /// CPU トレーナーの識別子。挑むボタンとモンスターの札の key に使う
  /// (テストと検証で押す相手を見分けるため)。
  final String opponentId;

  /// 相手の名前。
  final String title;

  /// 名前の下の補足 (挑む時の手持ちのレベル)。
  final String subtitle;

  /// 相手の手持ち (札にレベルを出さない。挑む時に自分の手持ちに合わせて決めるため)。
  final List<OwnedMonster> monsters;

  /// 挑む。手持ちがいない・挑む準備の間は null で、挑むボタンを押せなくする。
  final VoidCallback? onChallenge;

  @override
  Widget build(BuildContext context) => DecoratedBox(
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
                    Text(title, style: SnapmonTextStyles.label),
                    Text(subtitle, style: SnapmonTextStyles.small),
                  ],
                ),
              ),
              FilledButton(
                key: Key('challenge-$opponentId'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  shape: const RoundedRectangleBorder(
                    borderRadius: SnapmonRadii.tag,
                  ),
                  textStyle: SnapmonTextStyles.caption,
                ),
                onPressed: onChallenge,
                child: Text(context.l10n.opponentChallenge),
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
                  key: Key(
                    'opponent-monster-$opponentId-${monster.definition.id}',
                  ),
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

/// モンスターの名前の小さな札。
class _MonsterChip extends StatelessWidget {
  const _MonsterChip({
    required super.key,
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
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: SnapmonRadii.button,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        detail == null ? name : '$name  $detail',
        style: SnapmonTextStyles.small.copyWith(color: textColor),
      ),
    ),
  );
}
