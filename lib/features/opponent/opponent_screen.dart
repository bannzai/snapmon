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
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../home/home_shell.dart';
import '../result/result_screen.dart';
import '../share/card_sharer.dart';
import 'battle_definitions.dart';
import 'cpu_party.dart';
import 'pvp_client.dart';

/// 対戦の画面 (モックの Pvp.dc.html)。自分のアイコン・表示名と戦績、自分の手持ちを出し、「ランダムな相手と戦う」で
/// 初回のバトルと同じ決め方 ([chooseRandomCpuOpponent]) で CPU の相手を決めて挑む。相手の一覧は出さない
/// (対戦の相手は毎回ランダム。issue #217)。他のユーザーの手持ち (Functions の fetchOpponents) は相手にしない
/// (本人の操作なしに他人の手持ちを CPU に操作させないため。issue #130)。
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

  /// 見本データ (CPU トレーナーの名前と、CPU の手持ちにする見本のモンスター)。
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

  /// 乱数で決めた CPU の相手に挑む。挑んでいる間に呼ばれた時は何もしない。
  Future<void> _challengeRandomOpponent() async {
    if (_isChallenging) {
      return;
    }
    setState(() => _isChallenging = true);
    try {
      await _prepareAndStartBattle();
    } finally {
      if (mounted) {
        setState(() => _isChallenging = false);
      }
    }
  }

  /// 定義を読み直してから、乱数で決めた CPU の相手との対戦の画面を開き、閉じるまで待つ。
  Future<void> _prepareAndStartBattle() async {
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
    // 押すたびに別の相手・別の展開にするため、相手を決める seed とバトルの seed は毎回作る。
    // 値の範囲は DeterministicRandom の状態 (32 bit) に合わせた。
    // Web (JavaScript) ではシフトが 32 bit に切り詰められ `1 << 32` が 0 になるため、上限は整数リテラルで書く
    final playerParty = dexStore.party;
    final cpuOpponent = chooseRandomCpuOpponent(
      sampleData: widget.sampleData,
      playerParty: playerParty,
      randomSeed: math.Random().nextInt(0x100000000),
    );
    final action = await Navigator.of(context).push(
      MaterialPageRoute<BattleScreenAction>(
        builder: (context) => BattleScreen(
          playerParty: playerParty,
          opponentParty: cpuOpponent.opponentParty,
          opponentKind: BattleOpponentKind.cpu,
          definitions: definitions,
          randomSeed: math.Random().nextInt(0x100000000),
          battleRecorder: widget.battleRecorder,
          onPlayerLevelsChanged: dexStore.updateLevels,
          cardSharer: widget.cardSharer,
          firstBattleBornMonster: null,
          firstBattleMonsterIsNewlyBorn: false,
          playerProfile: _playerProfile,
          opponentDisplayName: cpuOpponent.opponentName,
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
          FilledButton.icon(
            key: const Key('random-battle'),
            onPressed: canChallenge ? _challengeRandomOpponent : null,
            icon: const Icon(Icons.shuffle),
            label: Text(context.l10n.opponentRandomBattle),
          ),
        ],
      );
    },
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
