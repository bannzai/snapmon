import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/monster_parts.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import 'card_sharer.dart';

/// 共有する図鑑のカード。モンスターの絵・名前・レベル・属性・ステータスと、snapmon のロゴ・紹介ページの URL を描く。
/// 絵は [artImagesByPath] の切り出した被写体の画像 (元の写真の一部または全体のこともある) を使い、Storage から読む部品
/// (StorageImage) を使わない (画面に出さずに PNG に描くため、読み込み済みの画像だけで描く)。名前と図鑑の文章が AI の生成である表示は描かない
/// (アプリのどの画面にも出さず、開示は利用規約・プライバシーポリシー・ストアの説明文で行うため。DIRECTION.md「決めたこと」2026-10-29・2026-10-30)。
class MonsterShareCard extends StatelessWidget {
  /// [monster] の共有するカードを作る。
  const MonsterShareCard({
    super.key,
    required this.monster,
    required this.artImagesByPath,
    required this.definitions,
    required this.format,
  });

  /// カードに描くモンスター。
  final OwnedMonster monster;

  /// 切り出した被写体の画像 (デコード済み) を Storage のパス ([OwnedMonster.artPath]) ごとに引く表。
  final Map<String, ui.Image> artImagesByPath;

  /// 属性・技の定義。
  final MasterData definitions;

  /// カード画像の形。
  final ShareCardFormat format;

  @override
  Widget build(BuildContext context) {
    final definition = monster.definition;
    final stats = calculateStats(
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      level: monster.level,
      statCalculationVersion: definition.statCalculationVersion,
    );
    final elementTypeTags = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final elementTypeID in definition.elementTypeIDs)
          ElementTypeTag(
            elementTypeID: elementTypeID,
            definitions: definitions,
          ),
      ],
    );
    final statValues = [
      (context.l10n.statHitPoints, stats.hitPoints),
      (context.l10n.statAttack, stats.attack),
      (context.l10n.statDefense, stats.defense),
      (context.l10n.statSpeed, stats.speed),
      (context.l10n.statAccuracy, stats.accuracy),
    ];
    return ColoredBox(
      color: SnapmonColors.background,
      child: switch (format) {
        ShareCardFormat.portrait => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Logo(),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: SnapmonColors.card,
                    borderRadius: SnapmonRadii.panel,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      definition.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SnapmonTextStyles.cardTitle,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.commonLevel(monster.level),
                                      style: SnapmonTextStyles.caption.copyWith(
                                        color: SnapmonColors.textOnCardMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 属性のタグは自分の幅だけを取り、残りを名前に渡す。上限の半分は、直す前の Flexible が
                              // 名前と分け合っていた幅で、属性が多い時はその幅の中で折り返す
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth / 2,
                                ),
                                child: elementTypeTags,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: _ShareCardMonsterArt(
                                monster: monster,
                                artImagesByPath: artImagesByPath,
                                backgroundColor: SnapmonColors.cardSubtle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _StatBoxes(
                          statValues: statValues,
                          boxColor: SnapmonColors.cardSubtle,
                          labelColor: SnapmonColors.textOnCardMuted,
                          valueColor: SnapmonColors.textOnCard,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          definition.encyclopediaText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: SnapmonTextStyles.body.copyWith(
                            color: SnapmonColors.textOnCardBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _LandingPageAddress(textAlign: TextAlign.center),
            ],
          ),
        ),
        ShareCardFormat.landscape => Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: SnapmonColors.card,
                    borderRadius: SnapmonRadii.panel,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _ShareCardMonsterArt(
                      monster: monster,
                      artImagesByPath: artImagesByPath,
                      backgroundColor: SnapmonColors.cardSubtle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 10),
                    Text(
                      definition.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SnapmonTextStyles.cardTitle.copyWith(
                        color: SnapmonColors.textOnBackground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          context.l10n.commonLevel(monster.level),
                          style: SnapmonTextStyles.caption,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: elementTypeTags),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatBoxes(
                      statValues: statValues,
                      boxColor: SnapmonColors.surface,
                      labelColor: SnapmonColors.textMuted,
                      valueColor: SnapmonColors.textOnBackground,
                    ),
                    const Spacer(),
                    const _LandingPageAddress(textAlign: TextAlign.start),
                  ],
                ),
              ),
            ],
          ),
        ),
      },
    );
  }
}

/// 共有するバトルの結果のカード。勝ち負け・相手の手持ちの名前と、自分の手持ちの絵・名前・レベル・属性・技の枠の技、
/// snapmon のロゴ・紹介ページの URL を描く。自分の手持ちの絵を主役にし、勝ち負けと相手の名前の残りの面を手持ちに使う
/// (https://github.com/bannzai/snapmon/issues/346 )。絵の扱いは [MonsterShareCard] と同じで、AI の生成である表示も描かない。
class BattleResultShareCard extends StatelessWidget {
  /// バトルの結果の共有するカードを作る。
  const BattleResultShareCard({
    super.key,
    required this.winner,
    required this.playerParty,
    required this.appliedLevels,
    required this.opponentParty,
    required this.artImagesByPath,
    required this.definitions,
    required this.format,
  });

  /// 勝った陣営。
  final BattleSideID winner;

  /// バトルの前の自分の手持ち (上がる前のレベルを出すため)。
  final List<OwnedMonster> playerParty;

  /// 確定した自分のモンスターのレベル (monsterID ごと)。確定していない間 (記録の待ち・失敗) は空で、
  /// 勝敗の画面と同じく上がった後のレベルを出さない。
  final Map<String, int> appliedLevels;

  /// 相手の手持ち (名前だけを出す)。
  final List<OwnedMonster> opponentParty;

  /// 切り出した被写体の画像 (デコード済み) を Storage のパス ([OwnedMonster.artPath]) ごとに引く表。
  final Map<String, ui.Image> artImagesByPath;

  /// 属性・技の定義。
  final MasterData definitions;

  /// カード画像の形。
  final ShareCardFormat format;

  /// [monster] 1 体の枠。絵と、名前・レベル (確定したレベルがあれば上がり方)・属性・技の枠の技を描く。
  /// 技は描くレベルと同じレベル (確定したレベルがあればそのレベル) の技の枠 ([equippedLearnsetEntries]) で引く。
  /// [direction] は絵と文字を並べる向き、[moveColumnCount] は技を並べる列の数、[nameStyle] は名前の文字。
  Widget _partyMonsterPanel({
    required AppLocalizations l10n,
    required OwnedMonster monster,
    required Axis direction,
    required int moveColumnCount,
    required TextStyle nameStyle,
  }) {
    final appliedLevel = appliedLevels[monster.definition.id];
    return _PartyMonsterPanel(
      monster: monster,
      levelText: appliedLevel == null
          ? l10n.commonLevel(monster.level)
          : l10n.commonLevelUp(monster.level, appliedLevel),
      moves: [
        for (final moveID in equippedLearnsetEntries(
          learnset: monster.definition.learnset,
          actionCardMoveIDs: monster.actionCardMoveIDs,
          selectedMoveIDs: monster.selectedMoveIDs,
          level: appliedLevel ?? monster.level,
        ))
          definitions.moveByID(moveID: moveID),
      ],
      artImagesByPath: artImagesByPath,
      definitions: definitions,
      direction: direction,
      moveColumnCount: moveColumnCount,
      nameStyle: nameStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultText = Text(
      winner == BattleSideID.player
          ? context.l10n.battleWon
          : context.l10n.battleLost,
      style: SnapmonTextStyles.screenTitle.copyWith(
        fontSize: switch (format) {
          ShareCardFormat.portrait => 56,
          ShareCardFormat.landscape => 40,
        },
        color: winner == BattleSideID.player
            ? SnapmonColors.accent
            : SnapmonColors.hitPointsLoss,
      ),
    );
    final opponentText = Text(
      context.l10n.shareVersusOpponents(
        opponentParty
            .map((monster) => monster.definition.name)
            .join(context.l10n.shareOpponentSeparator),
      ),
      maxLines: switch (format) {
        ShareCardFormat.portrait => 2,
        ShareCardFormat.landscape => 3,
      },
      overflow: TextOverflow.ellipsis,
      style: SnapmonTextStyles.label,
    );
    // 2 体以上の時の名前の文字。1 体の時は図鑑のカードと同じ大きな名前 (cardTitle) にする
    final partyNameStyle = SnapmonTextStyles.label.copyWith(
      color: SnapmonColors.textOnCard,
    );
    return ColoredBox(
      color: SnapmonColors.background,
      child: switch (format) {
        ShareCardFormat.portrait => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Logo(),
              const SizedBox(height: 16),
              resultText,
              const SizedBox(height: 6),
              opponentText,
              const SizedBox(height: 16),
              // 1 体の時は絵を上に大きく置き、2 体以上の時は残りの高さを分けた行の左に絵を置く
              if (playerParty.length == 1)
                Expanded(
                  child: _partyMonsterPanel(
                    l10n: context.l10n,
                    monster: playerParty.single,
                    direction: Axis.vertical,
                    moveColumnCount: 2,
                    nameStyle: SnapmonTextStyles.cardTitle,
                  ),
                )
              else
                for (final (index, monster) in playerParty.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  Expanded(
                    child: _partyMonsterPanel(
                      l10n: context.l10n,
                      monster: monster,
                      direction: Axis.horizontal,
                      moveColumnCount: 1,
                      nameStyle: partyNameStyle,
                    ),
                  ),
                ],
              const SizedBox(height: 12),
              const _LandingPageAddress(textAlign: TextAlign.center),
            ],
          ),
        ),
        ShareCardFormat.landscape => Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 勝ち負けと相手の名前を左の列に寄せ、手持ちの枠にカードの高さを全部使う。
              // 幅 140 は、ロゴ (約 110) が入り、3 体の時の絵の一辺 (約 110) を残せる幅
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 12),
                    FittedBox(fit: BoxFit.scaleDown, child: resultText),
                    const SizedBox(height: 6),
                    opponentText,
                    const Spacer(),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _LandingPageAddress(textAlign: TextAlign.start),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 1 体の時は絵を左に大きく置き、2 体以上の時は残りの幅を分けた列の上に絵を置く
              if (playerParty.length == 1)
                Expanded(
                  child: _partyMonsterPanel(
                    l10n: context.l10n,
                    monster: playerParty.single,
                    direction: Axis.horizontal,
                    moveColumnCount: 1,
                    nameStyle: partyNameStyle,
                  ),
                )
              else
                for (final (index, monster) in playerParty.indexed) ...[
                  if (index > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _partyMonsterPanel(
                      l10n: context.l10n,
                      monster: monster,
                      direction: Axis.vertical,
                      // 2 体の時は技を 2 列にして絵の高さを残し、3 体の時は枠の幅が狭いため 1 列にして文字の大きさを残す
                      moveColumnCount: playerParty.length == 2 ? 2 : 1,
                      nameStyle: partyNameStyle,
                    ),
                  ),
                ],
            ],
          ),
        ),
      },
    );
  }
}

/// バトルの結果のカードの、自分の手持ち 1 体の枠。絵を枠に入る最大の正方形で描き、残りに名前・レベル・属性・技を描く。
/// 文字は枠に入らない時に全体を縮める (名前や技を `...` で切らず、枠からはみ出させないため)。
class _PartyMonsterPanel extends StatelessWidget {
  const _PartyMonsterPanel({
    required this.monster,
    required this.levelText,
    required this.moves,
    required this.artImagesByPath,
    required this.definitions,
    required this.direction,
    required this.moveColumnCount,
    required this.nameStyle,
  });

  /// 描くモンスター。
  final OwnedMonster monster;

  /// レベルの表示 (確定したレベルがあれば上がり方)。
  final String levelText;

  /// 技の枠の技 (枠の順)。
  final List<Move> moves;

  /// 切り出した被写体の画像 (デコード済み) を Storage のパス ([OwnedMonster.artPath]) ごとに引く表。
  final Map<String, ui.Image> artImagesByPath;

  /// 属性の名前を引く定義。
  final MasterData definitions;

  /// 絵と文字を並べる向き。横は絵を左に、縦は絵を上に置く。
  final Axis direction;

  /// 技を並べる列の数。
  final int moveColumnCount;

  /// 名前の文字。
  final TextStyle nameStyle;

  /// 横に並べる時に、絵の一辺が枠の幅に占める割合の上限。文字の側に枠の幅の 4 割を残し、
  /// 名前と技 (標準で幅 130 ほど) を読める大きさで描けるようにする。
  static const double maximumHorizontalArtWidthRatio = 0.6;

  @override
  Widget build(BuildContext context) {
    final art = _ShareCardMonsterArt(
      monster: monster,
      artImagesByPath: artImagesByPath,
      backgroundColor: SnapmonColors.cardSubtle,
    );
    final info = FittedBox(
      fit: BoxFit.scaleDown,
      // 横に並べる時は絵の右に左寄せで、縦に並べる時は中央に置いた絵の下に中央で置く
      alignment: switch (direction) {
        Axis.horizontal => Alignment.centerLeft,
        Axis.vertical => Alignment.center,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(monster.definition.name, style: nameStyle),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                levelText,
                style: SnapmonTextStyles.caption.copyWith(
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
              for (final elementTypeID
                  in monster.definition.elementTypeIDs) ...[
                const SizedBox(width: 6),
                ElementTypeTag(
                  elementTypeID: elementTypeID,
                  definitions: definitions,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // 技の枠 (2 列 × 2 行) と同じく左上から右へ並べる。空の枠は描かない
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < moveColumnCount; column++) ...[
                if (column > 0) const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 3,
                  children: [
                    for (final (index, move) in moves.indexed)
                      if (index % moveColumnCount == column)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElementTypeIcon(
                              elementTypeID: move.elementTypeID,
                              definitions: definitions,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              move.displayName,
                              style: SnapmonTextStyles.caption.copyWith(
                                color: SnapmonColors.textOnCard,
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SnapmonColors.card,
        borderRadius: SnapmonRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: switch (direction) {
          Axis.horizontal => LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox.square(
                  dimension: math.min(
                    constraints.maxHeight,
                    constraints.maxWidth * maximumHorizontalArtWidthRatio,
                  ),
                  child: art,
                ),
                const SizedBox(width: 12),
                Expanded(child: info),
              ],
            ),
          ),
          Axis.vertical => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(child: AspectRatio(aspectRatio: 1, child: art)),
              ),
              const SizedBox(height: 8),
              info,
            ],
          ),
        },
      ),
    );
  }
}

/// カードの左上の snapmon のロゴ。
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Text(
    'snapmon',
    style: SnapmonTextStyles.logo.copyWith(color: SnapmonColors.accent),
  );
}

/// カードに入れる紹介ページの URL (スキームを省いた表示)。
class _LandingPageAddress extends StatelessWidget {
  const _LandingPageAddress({required this.textAlign});

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Text(
    '${landingPageUri.host}${landingPageUri.path}',
    textAlign: textAlign,
    style: SnapmonTextStyles.caption,
  );
}

/// カードの中のモンスターの絵。切り出した被写体の画像があれば [artImagesByPath] から引いて描き
/// (図鑑のカードと同じ [MonsterArtImage])、無ければ仮の絵を描く。
class _ShareCardMonsterArt extends StatelessWidget {
  const _ShareCardMonsterArt({
    required this.monster,
    required this.artImagesByPath,
    required this.backgroundColor,
  });

  final OwnedMonster monster;
  final Map<String, ui.Image> artImagesByPath;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final artPath = monster.artPath;
    return artPath == null
        ? PlaceholderMonsterArt(
            definition: monster.definition,
            backgroundColor: backgroundColor,
          )
        : MonsterArtImage(
            artImage:
                artImagesByPath[artPath] ??
                (throw StateError('$artPath の画像を読み込んでいない')),
            backgroundColor: backgroundColor,
          );
  }
}

/// HP・攻撃・防御・素早さ・命中の 5 つの枠。
class _StatBoxes extends StatelessWidget {
  const _StatBoxes({
    required this.statValues,
    required this.boxColor,
    required this.labelColor,
    required this.valueColor,
  });

  /// 並べるステータスの名前と値。
  final List<(String, int)> statValues;
  final Color boxColor;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, (label, value)) in statValues.indexed) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: boxColor,
              borderRadius: SnapmonRadii.button,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    label,
                    style: SnapmonTextStyles.small.copyWith(color: labelColor),
                  ),
                  Text(
                    '$value',
                    style: SnapmonTextStyles.statValue.copyWith(
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
