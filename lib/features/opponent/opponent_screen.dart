import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/master/master_data.dart';
import '../../l10n/l10n.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/trainer_icon.dart';
import '../battle/battle_recorder.dart';
import '../battle/battle_screen.dart';
import '../capture/first_battle.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../home/home_shell.dart';
import '../result/monster_detail_card.dart';
import '../result/result_screen.dart';
import '../share/card_sharer.dart';
import 'battle_definitions.dart';
import 'cpu_party.dart';
import 'pvp_client.dart';

/// 対戦相手を選ぶ画面 (モックの Pvp.dc.html)。見本データの CPU トレーナーを先頭から [_opponentSlotCount] 人並べ、自分のアイコン・表示名と戦績を出す。
/// 「自動で相手を決めて戦う」は、初回のバトルと同じ選び方で CPU トレーナーを決めて挑む。
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

  /// 設定画面を開き、閉じるまで待つ (閉じた後にプロフィールを読み直すため)。
  final Future<void> Function() onOpenSettings;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 戦績とプロフィールの読み込み。
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

  /// 自分の戦績 (勝ち数と負け数)。最初の読み込みの途中・ログインが無い時・読めなかった時は null
  /// (読めなかった時は古い勝敗を今の値として出さないため)。
  /// 読み直しの途中は前の値のままで、結果が届いた時に置き換える (プロフィールの札と同じく、バトルのたびに行が消えて出ないように)。
  ({int wins, int losses})? _battleRecord;

  /// 最後の戦績の読み込みの失敗。読めた時は null。
  Object? _battleRecordError;

  /// 最後に始めた戦績の読み込みの番号。前の読み込みの結果が後から届いても反映しないために持つ。
  int _latestBattleRecordLoadNumber = 0;

  /// 自分のアイコンと表示名。最初の読み込みの途中・ログインが無い時・読めなかった時は null で、自分の札を出さない
  /// (読めなくても挑めるようにするため。読めなかった理由はプロフィール画面の入口 (設定) に出る)。
  /// 読み直しの途中は前の値のままで、結果が届いた時に置き換える (設定を閉じるたびに札が消えて戦績の行が動かないように)。
  PlayerProfile? _playerProfile;

  /// 最後に始めたプロフィールの読み込みの番号。前の読み込みの結果が後から届いても反映しないために持つ。
  int _latestPlayerProfileLoadNumber = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBattleRecord());
    unawaited(_loadPlayerProfile());
  }

  /// 自分のアイコンと表示名を読む。最後に始めた読み込みの結果だけを [_playerProfile] に反映する。
  Future<void> _loadPlayerProfile() async {
    final loadNumber = ++_latestPlayerProfileLoadNumber;
    try {
      final profile = await widget.pvpClient.fetchProfile();
      if (mounted && loadNumber == _latestPlayerProfileLoadNumber) {
        setState(() => _playerProfile = profile);
      }
    } catch (error) {
      debugPrint('プロフィールを読めませんでした: $error');
      if (mounted && loadNumber == _latestPlayerProfileLoadNumber) {
        setState(() => _playerProfile = null);
      }
    }
  }

  /// 設定画面を開き、閉じたらプロフィールを読み直す (設定のプロフィール画面で変えた値を出すため)。
  Future<void> _openSettings() async {
    await widget.onOpenSettings();
    unawaited(_loadPlayerProfile());
  }

  /// 自分の戦績を読む。最後に始めた読み込みの結果だけを [_battleRecord] と [_battleRecordError] に反映する。
  Future<void> _loadBattleRecord() async {
    final loadNumber = ++_latestBattleRecordLoadNumber;
    try {
      final battleRecord = await widget.pvpClient.fetchBattleRecord();
      if (mounted && loadNumber == _latestBattleRecordLoadNumber) {
        setState(() {
          _battleRecord = battleRecord;
          _battleRecordError = null;
        });
      }
    } catch (error) {
      if (mounted && loadNumber == _latestBattleRecordLoadNumber) {
        setState(() {
          _battleRecord = null;
          _battleRecordError = error;
        });
      }
    }
  }

  void _showMessage({required String message}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// CPU トレーナー [cpuTrainer] の手持ちの見本のモンスター (レベルは見本のまま)。
  List<OwnedMonster> _sampleMonsters({required SampleOpponent cpuTrainer}) => [
    for (final monsterId in cpuTrainer.monsterIds)
      widget.sampleData.monsterById(monsterId: monsterId),
  ];

  /// 自分の手持ちと同じ絵の見本のモンスターを持たない CPU トレーナーから乱数で選んで挑む
  /// (初回のバトルと同じ選び方。lib/features/capture/first_battle.dart)。
  Future<void> _challengeAutomatically() => _challenge(
    cpuTrainer: chooseFirstBattleCpuTrainer(
      cpuTrainers: excludeCpuTrainersWithSameArt(
        sampleData: widget.sampleData,
        playerParty: widget.dexStore.party,
      ),
      // 押すたびに別の相手になり得るよう、seed は毎回作る (範囲は挑む時の seed と同じ 32 bit)
      randomSeed: math.Random().nextInt(0x100000000),
    ),
  );

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
            monsters: _sampleMonsters(cpuTrainer: cpuTrainer),
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
          playerProfile: _playerProfile,
          opponentDisplayName: cpuTrainer.name,
        ),
      ),
    );
    unawaited(_loadBattleRecord());
    if (action == BattleScreenAction.openDex) {
      widget.onSelectTab(tab: HomeTab.dex);
    }
  }

  /// 自分の手持ちの [monster] を図鑑から開いた時と同じ画面で開く。手持ちに入れた・入れ替えた時は図鑑のタブを開く。
  Future<void> _openPartyMonster({required OwnedMonster monster}) async {
    final action = await Navigator.of(context).push(
      MaterialPageRoute<ResultScreenAction>(
        builder: (context) => ResultScreen(
          monster: monster,
          dexStore: widget.dexStore,
          origin: ResultScreenOrigin.dex,
          cardSharer: widget.cardSharer,
        ),
      ),
    );
    if (action == ResultScreenAction.openDex) {
      widget.onSelectTab(tab: HomeTab.dex);
    }
  }

  /// CPU トレーナーの手持ちの [monster] の詳細をボトムシートで出す。
  Future<void> _showOpponentMonster({required OwnedMonster monster}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: SnapmonColors.background,
        // カードは横長の画面 (Web のデスクトップ) では画面の高さを超え、シートが全面を覆うと閉じるために押す外側が無くなる。
        // 上の 15% を押せる外側として残す (シートの上の余白で閉じられると分かる程度の幅として選んだ)
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            key: Key('opponent-monster-detail-${monster.definition.id}'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: MonsterDetailCard(
              monster: monster,
              definitions: widget.dexStore.definitions,
            ),
          ),
        ),
      );

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
                onPressed: _openSettings,
                size: 44,
              ),
            ],
          ),
          if (_playerProfile != null ||
              battleRecord != null ||
              _battleRecordError != null) ...[
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
                // 自分の札と戦績を別の行に置き、英語の「Battle record」のような長い見出しでも名前を切らない (幅 390 の画面で確かめた)
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_playerProfile case final playerProfile?)
                      TrainerLabel(
                        key: const Key('opponent-tab-player-trainer'),
                        displayName: playerProfile.displayName,
                        iconPath: playerProfile.iconPath,
                      ),
                    if (_playerProfile != null &&
                        (battleRecord != null || _battleRecordError != null))
                      const SizedBox(height: 8),
                    if (battleRecord != null || _battleRecordError != null)
                      Row(
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
                  key: Key('party-monster-${monster.definition.id}'),
                  monster: monster,
                  detail: context.l10n.commonLevel(monster.level),
                  color: SnapmonColors.card,
                  textColor: SnapmonColors.textOnCard,
                  onTap: () => _openPartyMonster(monster: monster),
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
          FilledButton.icon(
            key: const Key('auto-match'),
            onPressed: canChallenge ? _challengeAutomatically : null,
            icon: const Icon(Icons.shuffle),
            label: Text(context.l10n.opponentAutoMatch),
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
              // 詳細には挑む時と同じレベル (自分の手持ちの平均) を出す。手持ちが空の時は挑めないため、見本のレベルのまま出す
              monsters: party.isEmpty
                  ? _sampleMonsters(cpuTrainer: cpuTrainer)
                  : buildCpuParty(
                      monsters: _sampleMonsters(cpuTrainer: cpuTrainer),
                      playerParty: party,
                    ),
              onMonsterTap: _showOpponentMonster,
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
    required this.onMonsterTap,
    required this.onChallenge,
  });

  /// CPU トレーナーの識別子。挑むボタンとモンスターの札の key に使う
  /// (テストと検証で押す相手を見分けるため)。
  final String opponentId;

  /// 相手の名前。CPU トレーナーはアイコンを持たないため、アイコンにはこの名前から既定の印を描く。
  final String title;

  /// 名前の下の補足 (挑む時の手持ちのレベル)。
  final String subtitle;

  /// 相手の手持ち (札にレベルを出さない。挑む時に自分の手持ちに合わせて決めるため)。
  final List<OwnedMonster> monsters;

  /// 手持ちの札を押した時に、押したモンスターを受け取る。
  final void Function({required OwnedMonster monster}) onMonsterTap;

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
              // 36: 対戦相手のカードの見出し (名前と手持ちの数の 2 行) と同じ高さで、見出しの左に並べるため
              TrainerIcon(displayName: title, iconPath: null, dimension: 36),
              // 10: モック (documents/design/mock-2026-10-21/Pvp.dc.html の CPU トレーナーの行) のアイコンと見出しの間隔に揃える
              const SizedBox(width: 10),
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
                  monster: monster,
                  detail: null,
                  color: SnapmonColors.surfaceRaised,
                  textColor: SnapmonColors.textOnBackground,
                  onTap: () => onMonsterTap(monster: monster),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// モンスターの絵と名前の小さな札。押すとそのモンスターの詳細を開く。
class _MonsterChip extends StatelessWidget {
  const _MonsterChip({
    required super.key,
    required this.monster,
    required this.detail,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  /// 絵と名前を出すモンスター。
  final OwnedMonster monster;

  /// 名前の後ろに添える補足 (レベル)。無ければ null。
  final String? detail;
  final Color color;
  final Color textColor;

  /// 押した時の処理。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: SnapmonRadii.button,
    child: InkWell(
      borderRadius: SnapmonRadii.button,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 絵は名前の 2 行分ほどの大きさにし、札を 3 つ並べても 1 行 (幅 390 の画面) に収まるようにした
            SizedBox.square(
              dimension: 32,
              child: ClipRRect(
                borderRadius: SnapmonRadii.tag,
                child: MonsterArt(
                  monster: monster,
                  backgroundColor: SnapmonColors.artBackground,
                ),
              ),
            ),
            // 8: モック (documents/design/mock-2026-10-21/Pvp.dc.html の手持ちの札) の絵と文字の間隔に揃える
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                detail == null
                    ? monster.definition.name
                    : '${monster.definition.name}  $detail',
                style: SnapmonTextStyles.small.copyWith(color: textColor),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
