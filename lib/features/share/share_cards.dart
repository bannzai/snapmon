import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import 'card_sharer.dart';

/// 共有する図鑑のカード。モンスターの絵・名前・レベル・属性・ステータスと、snapmon のロゴ・紹介ページの URL を描く。
/// 絵は [artImagesByPath] の切り出した被写体の画像 (元の写真の一部または全体のこともある) を使い、Storage から読む部品
/// (StorageImage) を使わない (画面に出さずに PNG に描くため、読み込み済みの画像だけで描く)。名前と図鑑の文章が AI の生成である表示は描かない
/// (SNS で見る人は本サービスの利用者ではないため。DIRECTION.md「決めたこと」2026-10-29)。
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
        for (final elementTypeId in definition.elementTypeIds)
          ElementTypeTag(
            elementTypeId: elementTypeId,
            definitions: definitions,
          ),
      ],
    );
    final statValues = [
      (context.l10n.statHitPoints, stats.hitPoints),
      (context.l10n.statAttack, stats.attack),
      (context.l10n.statDefense, stats.defense),
      (context.l10n.statSpeed, stats.speed),
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

/// 共有するバトルの結果のカード。勝ち負け・相手の手持ちの名前・自分の手持ちの絵と名前とレベルと、
/// snapmon のロゴ・紹介ページの URL を描く。絵と AI の生成の表示の扱いは [MonsterShareCard] と同じ。
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
  final BattleSideId winner;

  /// バトルの前の自分の手持ち (上がる前のレベルを出すため)。
  final List<OwnedMonster> playerParty;

  /// 確定した自分のモンスターのレベル (monsterId ごと)。確定していない間 (記録の待ち・失敗) は空で、
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

  /// [monster] のレベルの表示。確定したレベルがあれば上がり方を出す。
  String _levelText({
    required AppLocalizations l10n,
    required OwnedMonster monster,
  }) => switch (appliedLevels[monster.definition.id]) {
    final newLevel? => l10n.commonLevelUp(monster.level, newLevel),
    null => l10n.commonLevel(monster.level),
  };

  @override
  Widget build(BuildContext context) {
    final resultText = Text(
      winner == BattleSideId.player
          ? context.l10n.battleWon
          : context.l10n.battleLost,
      style: SnapmonTextStyles.screenTitle.copyWith(
        fontSize: switch (format) {
          ShareCardFormat.portrait => 56,
          ShareCardFormat.landscape => 40,
        },
        color: winner == BattleSideId.player
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
        ShareCardFormat.landscape => 1,
      },
      overflow: TextOverflow.ellipsis,
      style: SnapmonTextStyles.label,
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
              const SizedBox(height: 24),
              resultText,
              const SizedBox(height: 6),
              opponentText,
              const SizedBox(height: 20),
              for (final (index, monster) in playerParty.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                // 行の高さは中身に合わせる (属性の札が 2 行に折り返しても切れないように)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: SnapmonColors.card,
                    borderRadius: SnapmonRadii.card,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 92,
                          child: _ShareCardMonsterArt(
                            monster: monster,
                            artImagesByPath: artImagesByPath,
                            backgroundColor: SnapmonColors.cardSubtle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                monster.definition.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SnapmonTextStyles.label.copyWith(
                                  color: SnapmonColors.textOnCard,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _levelText(
                                  l10n: context.l10n,
                                  monster: monster,
                                ),
                                style: SnapmonTextStyles.caption.copyWith(
                                  color: SnapmonColors.textOnCardMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final elementTypeId
                                      in monster.definition.elementTypeIds)
                                    ElementTypeTag(
                                      elementTypeId: elementTypeId,
                                      definitions: definitions,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              const _LandingPageAddress(textAlign: TextAlign.center),
            ],
          ),
        ),
        ShareCardFormat.landscape => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  _Logo(),
                  Spacer(),
                  _LandingPageAddress(textAlign: TextAlign.end),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  resultText,
                  const SizedBox(width: 16),
                  Expanded(child: opponentText),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, monster) in playerParty.indexed) ...[
                      if (index > 0) const SizedBox(width: 10),
                      Expanded(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: SnapmonColors.card,
                            borderRadius: SnapmonRadii.card,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: _ShareCardMonsterArt(
                                        monster: monster,
                                        artImagesByPath: artImagesByPath,
                                        backgroundColor:
                                            SnapmonColors.cardSubtle,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  monster.definition.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SnapmonTextStyles.caption.copyWith(
                                    color: SnapmonColors.textOnCard,
                                  ),
                                ),
                                Text(
                                  _levelText(
                                    l10n: context.l10n,
                                    monster: monster,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SnapmonTextStyles.small.copyWith(
                                    color: SnapmonColors.textOnCardMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// HP・攻撃・防御・素早さの 4 つの枠。
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
