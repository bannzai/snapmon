import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/master/master_data.dart';
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
import '../settings/settings_screen.dart';
import 'cpu_party.dart';
import 'pvp_client.dart';
import 'pvp_opponent.dart';
import 'report_sheet.dart';

/// 対戦相手を選ぶ画面 (モックの Pvp.dc.html)。他のユーザーの手持ち (非同期 PvP。Functions の fetchOpponents が選ぶ最大 3 人) と
/// CPU トレーナーを並べ、自分の戦績を出す。相手のモンスターの長押しで通報、カードのメニューで通報とブロックができる。
/// 年齢の確認を通ったログインが無い時 (DEBUG ビルドでログインを飛ばした時) は、見本の対戦相手を他のユーザーの代わりに出し、
/// 通報・ブロックはこの画面から消すだけにする (送り先のサーバーが無いため)。
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
    required this.openUrl,
  });

  /// 見本データ (CPU トレーナーと、ログインが無い時の他のユーザーの代わり)。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 相手の取得・通報・ブロック・戦績。
  final PvpClient pvpClient;

  /// お問い合わせを開く。
  final OpenUrl openUrl;

  @override
  State<OpponentScreen> createState() => _OpponentScreenState();
}

/// 他のユーザーの相手の読み込みの状態。
sealed class _PvpOpponentsState {
  const _PvpOpponentsState();
}

/// 読み込んでいる。
class _PvpOpponentsLoading extends _PvpOpponentsState {
  const _PvpOpponentsLoading();
}

/// 読み込めた。[isSample] はログインが無く見本の対戦相手を代わりに出している時に true。
class _PvpOpponentsLoaded extends _PvpOpponentsState {
  const _PvpOpponentsLoaded({required this.opponents, required this.isSample});

  final List<PvpOpponent> opponents;
  final bool isSample;
}

/// 読み込めなかった。
class _PvpOpponentsFailed extends _PvpOpponentsState {
  const _PvpOpponentsFailed({required this.error});

  final Object error;
}

class _OpponentScreenState extends State<OpponentScreen> {
  /// 挑む準備 (定義の読み直し) から対戦の画面を閉じるまでの間か。間は挑む操作を受け付けない
  /// (連打で対戦の画面とバトルの記録が重なるため)。
  bool _isChallenging = false;

  /// 他のユーザーの相手。手持ちが空の間は読まない (Functions が自分の手持ちの平均レベルから選ぶため) ので null。
  _PvpOpponentsState? _pvpOpponentsState;

  /// 最後に始めた相手の読み込み。後から始めた読み込みがある時は、古い結果で上書きしない。
  int _pvpOpponentsRequestNumber = 0;

  /// 自分の戦績 (勝ち数と負け数)。読み込み中・ログインが無い時は null。
  ({int wins, int losses})? _battleRecord;

  /// 戦績の読み込みの失敗。
  Object? _battleRecordError;

  @override
  void initState() {
    super.initState();
    widget.dexStore.addListener(_loadOpponentsWhenPartyAppears);
    _loadOpponentsWhenPartyAppears();
    unawaited(_loadBattleRecord());
  }

  @override
  void dispose() {
    widget.dexStore.removeListener(_loadOpponentsWhenPartyAppears);
    super.dispose();
  }

  /// 手持ちがあって相手をまだ読んでいなければ読む (図鑑と手持ちは Firestore から後から届くため、届いた時にも呼ぶ)。
  /// initState と図鑑の変更の通知から呼ぶため setState を使わない (通知の後は図鑑の ListenableBuilder が描き直す)。
  void _loadOpponentsWhenPartyAppears() {
    if (_pvpOpponentsState == null && widget.dexStore.party.isNotEmpty) {
      _pvpOpponentsState = const _PvpOpponentsLoading();
      unawaited(_fetchOpponents());
    }
  }

  /// 他のユーザーの相手を読み直す (再読み込みのボタン)。
  Future<void> _loadOpponents() async {
    setState(() => _pvpOpponentsState = const _PvpOpponentsLoading());
    await _fetchOpponents();
  }

  /// 他のユーザーの相手を読み、読めた相手か失敗を画面に出す。ログインが無い時は見本の対戦相手を代わりに出す。
  Future<void> _fetchOpponents() async {
    final requestNumber = ++_pvpOpponentsRequestNumber;
    _PvpOpponentsState nextState;
    try {
      final opponents = await widget.pvpClient.fetchOpponents();
      nextState = _PvpOpponentsLoaded(
        opponents: opponents ?? _sampleOpponents(),
        isSample: opponents == null,
      );
    } catch (error) {
      nextState = _PvpOpponentsFailed(error: error);
    }
    if (mounted && requestNumber == _pvpOpponentsRequestNumber) {
      setState(() => _pvpOpponentsState = nextState);
    }
  }

  /// ログインが無い時に他のユーザーの代わりに出す見本の対戦相手 (CPU トレーナー以外)。
  List<PvpOpponent> _sampleOpponents() => [
    for (final opponent in widget.sampleData.opponents)
      if (opponent.id != cpuOpponentId)
        PvpOpponent(
          opponentUid: opponent.id,
          displayName: opponent.name,
          monsters: [
            for (final monsterId in opponent.monsterIds)
              widget.sampleData.monsterById(monsterId: monsterId),
          ],
        ),
  ];

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

  /// [opponentUid] の相手をこの画面の候補から消す (通報・ブロックの後。サーバーも次の読み込みから外す)。
  void _removeOpponent({required String opponentUid}) {
    final state = _pvpOpponentsState;
    if (state is! _PvpOpponentsLoaded) {
      return;
    }
    setState(
      () => _pvpOpponentsState = _PvpOpponentsLoaded(
        opponents: [
          for (final opponent in state.opponents)
            if (opponent.opponentUid != opponentUid) opponent,
        ],
        isSample: state.isSample,
      ),
    );
  }

  bool get _isShowingSampleOpponents => switch (_pvpOpponentsState) {
    _PvpOpponentsLoaded(:final isSample) => isSample,
    _ => false,
  };

  void _showMessage({required String message}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// お問い合わせを開く。開けなかった時はそのことを出す。
  Future<void> _openContact() async {
    try {
      if (!await widget.openUrl(uri: contactUri) && mounted) {
        _showMessage(message: '$contactUri を開けませんでした');
      }
    } on Exception catch (error) {
      if (mounted) {
        _showMessage(message: error.toString());
      }
    }
  }

  /// [opponent] のモンスター [monster] を通報するシートを開き、送れたら候補から消す。
  /// 送っている間にシートを閉じられても通報は届くため、候補から消すのはシートの結果ではなく送れた時に行う。
  Future<void> _report({
    required PvpOpponent opponent,
    required OwnedMonster monster,
  }) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SnapmonColors.surface,
      builder: (context) => ReportSheet(
        monsterName: monster.definition.name,
        onSubmit: ({required reason}) async {
          if (!_isShowingSampleOpponents) {
            await widget.pvpClient.reportMonster(
              monsterOwnerUid: opponent.opponentUid,
              monsterId: monster.definition.id,
              reason: reason,
            );
          }
          if (mounted) {
            _removeOpponent(opponentUid: opponent.opponentUid);
            _showMessage(message: '通報しました');
          }
        },
        onOpenContact: _openContact,
      ),
    );
  }

  /// [opponent] をブロックするかを確かめ、ブロックしたら候補から消す。失敗した時はエラーをそのまま出す。
  Future<void> _block({required PvpOpponent opponent}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${opponent.displayName} をブロック'),
        content: const Text('このトレーナーと互いに対戦の相手に出なくなります'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          TextButton(
            key: const Key('block-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ブロックする'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      if (!_isShowingSampleOpponents) {
        await widget.pvpClient.blockUser(blockedUid: opponent.opponentUid);
      }
      if (mounted) {
        _removeOpponent(opponentUid: opponent.opponentUid);
        _showMessage(message: 'ブロックしました');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(message: error.toString());
      }
    }
  }

  /// 通報とブロックのやり方と、お問い合わせの入口を出す。
  Future<void> _showReportHelp() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnapmonColors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '通報 · ブロック',
              style: SnapmonTextStyles.cardTitle.copyWith(
                color: SnapmonColors.textOnBackground,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '相手のモンスターを長押しすると通報できます\nカードの右上のボタンから通報とブロックができます',
              style: SnapmonTextStyles.body,
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('report-help-contact'),
              onPressed: _openContact,
              child: const Text('お問い合わせ'),
            ),
          ],
        ),
      ),
    ),
  );

  /// [opponent] に挑む。挑んでいる間に呼ばれた時は何もしない。
  Future<void> _challenge({required _Challenger opponent}) async {
    if (_isChallenging) {
      return;
    }
    setState(() => _isChallenging = true);
    try {
      await _prepareAndStartBattle(opponent: opponent);
    } finally {
      if (mounted) {
        setState(() => _isChallenging = false);
      }
    }
  }

  /// 定義を読み直して (他のユーザーの相手は、相手のモンスターが参照するその場で作った定義も足して) から
  /// [opponent] との対戦の画面を開き、閉じるまで待つ。
  Future<void> _prepareAndStartBattle({required _Challenger opponent}) async {
    final dexStore = widget.dexStore;
    final MasterData definitions;
    // 相性表は対戦時点の最新の版を使う (documents/adr/0001-tech-stack.md)。読み直せない時は古い版で戦わせず、エラーをそのまま出す
    try {
      await dexStore.refreshDefinitions();
      definitions = switch (opponent) {
        // 見本の対戦相手の属性・技は master と同じ ID・同じ値のため (test/sample/sample_data_test.dart)、
        // 図鑑の定義 (サーバーの master と図鑑が参照する定義) から両者を引ける
        _CpuChallenger() => dexStore.definitions,
        _PvpChallenger(:final pvpOpponent) =>
          await widget.pvpClient.fetchDefinitions(
            base: dexStore.definitions,
            definitionIds: [
              for (final monster in pvpOpponent.monsters)
                ...monster.definitionIds,
            ],
          ),
      };
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
          opponentParty: switch (opponent) {
            _CpuChallenger(:final sampleOpponent) => buildCpuParty(
              monsters: [
                for (final monsterId in sampleOpponent.monsterIds)
                  widget.sampleData.monsterById(monsterId: monsterId),
              ],
              playerParty: playerParty,
              randomSeed: randomSeed,
            ),
            _PvpChallenger(:final pvpOpponent) => pvpOpponent.monsters,
          },
          opponentKind: switch (opponent) {
            _CpuChallenger() => BattleOpponentKind.cpu,
            _PvpChallenger() => BattleOpponentKind.pvp,
          },
          definitions: definitions,
          randomSeed: randomSeed,
          battleRecorder: widget.battleRecorder,
          onPlayerLevelsChanged: dexStore.updateLevels,
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
      final cpuOpponent = widget.sampleData.opponents.firstWhere(
        (opponent) => opponent.id == cpuOpponentId,
        orElse: () => throw StateError('見本データに CPU トレーナーが無い'),
      );
      final battleRecord = _battleRecord;
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
                    const Text('戦績', style: SnapmonTextStyles.caption),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        battleRecord == null
                            ? _battleRecordError.toString()
                            : '${battleRecord.wins} 勝 ${battleRecord.losses} 敗',
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
                  key: null,
                  name: monster.definition.name,
                  detail: 'Lv. ${monster.level}',
                  color: SnapmonColors.card,
                  textColor: SnapmonColors.textOnCard,
                  onLongPress: null,
                ),
              Material(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.button,
                child: InkWell(
                  borderRadius: SnapmonRadii.button,
                  onTap: () => widget.onSelectTab(tab: HomeTab.dex),
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
          Row(
            children: [
              const Expanded(
                child: Text('相手をえらぶ', style: SnapmonTextStyles.caption),
              ),
              if (_pvpOpponentsState is _PvpOpponentsLoaded)
                TextButton(
                  key: const Key('reload-opponents'),
                  onPressed: _isChallenging ? null : _loadOpponents,
                  child: const Text('ほかの相手をさがす'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ..._buildPvpOpponents(canChallenge: canChallenge),
          _OpponentCard(
            key: const Key('opponent-card-$cpuOpponentId'),
            opponentId: cpuOpponentId,
            title: cpuOpponent.name,
            subtitle: party.isEmpty
                ? '手持ちのレベルに合わせる'
                : '平均 Lv. ${averagePartyLevel(party: party)} 前後',
            monsters: [
              for (final monsterId in cpuOpponent.monsterIds)
                widget.sampleData.monsterById(monsterId: monsterId),
            ],
            showsMonsterLevels: false,
            onChallenge: canChallenge
                ? () => _challenge(
                    opponent: _CpuChallenger(sampleOpponent: cpuOpponent),
                  )
                : null,
            onLongPressMonster: null,
            menu: null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('相手のモンスターに問題があれば', style: SnapmonTextStyles.small),
              ),
              TextButton(
                key: const Key('report-help'),
                onPressed: _showReportHelp,
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

  /// 他のユーザーの相手のカード (読み込みの状態に応じて、読み込み中・失敗・候補が無い時の文言)。
  List<Widget> _buildPvpOpponents({
    required bool canChallenge,
  }) => switch (_pvpOpponentsState) {
    null => const [],
    _PvpOpponentsLoading() => const [
      Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          'トレーナーをさがしています',
          key: Key('opponents-loading'),
          style: SnapmonTextStyles.small,
        ),
      ),
    ],
    _PvpOpponentsFailed(:final error) => [
      Text(
        error.toString(),
        key: const Key('opponents-error'),
        style: SnapmonTextStyles.small.copyWith(
          color: SnapmonColors.hitPointsLoss,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('retry-opponents'),
          onPressed: _loadOpponents,
          child: const Text('もう一度さがす'),
        ),
      ),
      const SizedBox(height: 10),
    ],
    _PvpOpponentsLoaded(:final opponents) when opponents.isEmpty => const [
      Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          'いま戦えるトレーナーがいません\nCPU トレーナーと戦えます',
          key: Key('opponents-empty'),
          style: SnapmonTextStyles.small,
        ),
      ),
    ],
    _PvpOpponentsLoaded(:final opponents) => [
      for (final opponent in opponents) ...[
        _OpponentCard(
          key: Key('opponent-card-${opponent.opponentUid}'),
          opponentId: opponent.opponentUid,
          title: opponent.displayName,
          subtitle: '平均 Lv. ${averagePartyLevel(party: opponent.monsters)}',
          monsters: opponent.monsters,
          showsMonsterLevels: true,
          onChallenge: canChallenge
              ? () =>
                    _challenge(opponent: _PvpChallenger(pvpOpponent: opponent))
              : null,
          onLongPressMonster: ({required monster}) =>
              _report(opponent: opponent, monster: monster),
          menu: PopupMenuButton<VoidCallback>(
            key: Key('opponent-menu-${opponent.opponentUid}'),
            tooltip: '通報 · ブロック',
            icon: const Icon(Icons.more_horiz, color: SnapmonColors.textMuted),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              for (final monster in opponent.monsters)
                PopupMenuItem(
                  value: () => _report(opponent: opponent, monster: monster),
                  child: Text('${monster.definition.name} を通報'),
                ),
              PopupMenuItem(
                key: Key('block-${opponent.opponentUid}'),
                value: () => _block(opponent: opponent),
                child: const Text('このトレーナーをブロック'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    ],
  };
}

/// 挑む相手。CPU トレーナーか、他のユーザーの手持ち。
sealed class _Challenger {
  const _Challenger();
}

/// CPU トレーナー (手持ちのレベルは挑む時に自分の手持ちに合わせる)。
class _CpuChallenger extends _Challenger {
  const _CpuChallenger({required this.sampleOpponent});

  final SampleOpponent sampleOpponent;
}

/// 他のユーザーの手持ち (相手の今のレベルのまま戦う)。
class _PvpChallenger extends _Challenger {
  const _PvpChallenger({required this.pvpOpponent});

  final PvpOpponent pvpOpponent;
}

/// 対戦相手 1 人のカード。
class _OpponentCard extends StatelessWidget {
  const _OpponentCard({
    required super.key,
    required this.opponentId,
    required this.title,
    required this.subtitle,
    required this.monsters,
    required this.showsMonsterLevels,
    required this.onChallenge,
    required this.onLongPressMonster,
    required this.menu,
  });

  /// 相手の識別子 (他のユーザーの uid か、見本の対戦相手の識別子)。挑むボタンとモンスターの札の key に使う
  /// (テストと検証で押す相手を見分けるため)。
  final String opponentId;

  /// 相手の名前。
  final String title;

  /// 名前の下の補足 (平均レベル)。
  final String subtitle;

  /// 相手の手持ち。
  final List<OwnedMonster> monsters;

  /// 手持ちの札にレベルを出すか (CPU トレーナーは挑む時にレベルを決めるため出さない)。
  final bool showsMonsterLevels;

  /// 挑む。手持ちがいない・挑む準備の間は null で、挑むボタンを押せなくする。
  final VoidCallback? onChallenge;

  /// 相手のモンスターを長押しした時 (通報)。CPU トレーナーは null。
  final void Function({required OwnedMonster monster})? onLongPressMonster;

  /// 右上のメニュー (通報・ブロック)。CPU トレーナーは null。
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final onLongPressMonster = this.onLongPressMonster;
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
                      Text(title, style: SnapmonTextStyles.label),
                      Text(subtitle, style: SnapmonTextStyles.small),
                    ],
                  ),
                ),
                ?menu,
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
                    key: Key(
                      'opponent-monster-$opponentId-${monster.definition.id}',
                    ),
                    name: monster.definition.name,
                    detail: showsMonsterLevels ? 'Lv. ${monster.level}' : null,
                    color: SnapmonColors.surfaceRaised,
                    textColor: SnapmonColors.textOnBackground,
                    onLongPress: onLongPressMonster == null
                        ? null
                        : () => onLongPressMonster(monster: monster),
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
    required super.key,
    required this.name,
    required this.detail,
    required this.color,
    required this.textColor,
    required this.onLongPress,
  });

  final String name;

  /// 名前の後ろに添える補足 (レベル)。無ければ null。
  final String? detail;
  final Color color;
  final Color textColor;

  /// 長押しした時 (相手のモンスターの通報)。無ければ null。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: SnapmonRadii.button,
    child: InkWell(
      borderRadius: SnapmonRadii.button,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          detail == null ? name : '$name  $detail',
          style: SnapmonTextStyles.small.copyWith(color: textColor),
        ),
      ),
    ),
  );
}
