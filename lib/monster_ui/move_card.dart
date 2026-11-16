import 'package:flutter/material.dart';

import '../domain/battle/move_special_effect.dart';
import '../domain/master/master_data.dart';
import '../domain/master/move.dart';
import '../l10n/l10n.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_text_styles.dart';
import 'monster_parts.dart';

/// 技の中身を 3 段で描く。1 段目は名前 (幅に入らなければ折り返す) と、右端に固定した属性のアイコン・今の相手への相性のアイコン、2 段目は威力、3 段目は特殊効果の説明と右に寄せた PP。
/// 段ごとに書体と色を変え、何が名前で何が属性かを読み分けられるようにする (https://github.com/bannzai/snapmon/issues/123 )。
/// バトルの技のボタンと、モンスターのカードの覚えている技の行で使う。地はカードの生成りの白を前提にする。
class MoveCard extends StatelessWidget {
  /// 技の 3 段の表示を作る。
  const MoveCard({
    super.key,
    required this.move,
    required this.remainingPowerPoints,
    required this.typeMultiplier,
    required this.definitions,
  });

  /// 描く技。
  final Move move;

  /// 残りの PP。バトルの外 (カードの覚えている技) では null で、その時は最大の PP だけを出す。
  final int? remainingPowerPoints;

  /// 今の相手の場のモンスターへの相性の倍率。属性のアイコンの右に上下の矢印のアイコンで出す
  /// (効果が抜群か今ひとつかを技を選ぶ前に分かるようにする。https://github.com/bannzai/snapmon/issues/241 )。
  /// バトルの外と相性が効かない技 (補助技・一撃必殺) は null で、出さない。
  final double? typeMultiplier;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // バトルの技のボタン (remainingPowerPoints がある) では、名前を左、属性と相性のアイコンを右端に置く。
      // 名前は幅に入らなければ折り返し (`...` で切らない)、アイコンは折り返さず 1 行目の右端に留まる
      // (bannzai の「カードのタイトルが長かったら 1 行に収めるように `...` にしないこと。アイコンは改行しない」。
      // https://github.com/bannzai/snapmon/issues/281 )。名前を Expanded にするため、大きい文字でも Row がはみ出さない。
      // モンスターのカードの覚えている技の行 (バトルの外) は issue #281 の「モンスターのカードの属性の札は変えない」のとおり、
      // 他の画面と同じ文字の属性の札のままにする (幅が広く、名前と札が 1 行に入る)
      if (remainingPowerPoints != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(move.displayName, style: SnapmonTextStyles.moveName),
            ),
            const SizedBox(width: 6),
            ElementTypeIcon(
              elementTypeID: move.elementTypeID,
              definitions: definitions,
            ),
            // 等倍は出さない (ログの「こうかは ばつぐんだ」「いまひとつ」と同じく、倍率が変わる時だけ知らせる。全部の技に出すと技の枠が埋まるため)
            if (typeMultiplier case final typeMultiplier?
                when typeMultiplier != 1) ...[
              const SizedBox(width: 4),
              TypeEffectivenessIcon(typeMultiplier: typeMultiplier),
            ],
          ],
        )
      else
        // 名前と札が 1 行に入らない幅 (大きい文字) では札を名前の下の行に送る。Row に並べると札が入らない時に名前が潰れてはみ出す
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(move.displayName, style: SnapmonTextStyles.moveName),
            ElementTypeTag(
              elementTypeID: move.elementTypeID,
              definitions: definitions,
            ),
          ],
        ),
      const SizedBox(height: 4),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${context.l10n.movePower} ',
              style: SnapmonTextStyles.small.copyWith(
                fontWeight: FontWeight.w400,
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
            TextSpan(
              text: '${move.power}',
              style: SnapmonTextStyles.label.copyWith(
                color: SnapmonColors.textOnCard,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (move.specialEffect case final specialEffect?)
            Expanded(
              child: Text(
                specialEffect.summary,
                style: SnapmonTextStyles.small.copyWith(
                  fontWeight: FontWeight.w400,
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          // PP は技を選ぶ判断に効くことが少ないため、威力より小さく細くして右下に置く。
          // 薄さは大きさと太さで出し、色は生成りの地で読める textOnCardMuted にする (暗い地の textMuted はコントラスト比 2.2 で読めない)。
          // 説明と PP は幅を半分ずつ分け、PP はその中で右に寄せる。Row の子のままだと大きい文字で PP が段からはみ出して例外になる。
          // PP の取り分を半分より狭くする (説明 3 : PP 2、上限 80px) と、横向きのスマホで文字を 2 倍にした時に PP が 3〜4 行に
          // 折り返して技のボタンが高くなり、スクロールしても押せなくなる (battle_screen_test の「横向きのスマホで文字を 2 倍にしても…
          // 技のボタンを押せる」で測った)。段の幅から上限を求めない (LayoutBuilder) のは、技のボタンが IntrinsicHeight の中にあり、
          // LayoutBuilder が intrinsic の高さを返せず描画が止まるため
          Flexible(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '${context.l10n.movePowerPoints} ${switch (remainingPowerPoints) {
                  final remainingPowerPoints? => '$remainingPowerPoints/${move.powerPoints}',
                  null => '${move.powerPoints}',
                }}',
                style: SnapmonTextStyles.small.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 今の相手への相性のアイコン。上下の矢印だけで、効果が抜群 (1 より大きい) か今ひとつ (1 より小さい) かを言葉を読まずに伝える
/// (https://github.com/bannzai/snapmon/issues/259 )。属性のアイコンと同じ大きさの丸にし、
/// 抜群は強調色の地に濃い矢印で技の中でいちばん目を引かせ、今ひとつは薄い地と薄い矢印で控えめに描く。
/// 倍率 (×2・×4・×0.5・×0.25) と「効果は抜群」「効果はいまひとつ」の言葉は読み上げの名前にだけ持つ。
/// 画面に出すと 2 列の技のボタンの幅に収まらず、使った後のログが同じ言葉を出して矢印の意味を教えるため
/// (倍率を消したのは bannzai の「なんなら数字もいらない気がする」。https://github.com/bannzai/snapmon/issues/281 )。
class TypeEffectivenessIcon extends StatelessWidget {
  /// 相性の倍率 [typeMultiplier] のアイコンを作る。技の枠と遊び方の画面 (lib/features/help/) が使う。
  const TypeEffectivenessIcon({super.key, required this.typeMultiplier});

  /// 相性の倍率 (等倍以外)。
  final double typeMultiplier;

  @override
  Widget build(BuildContext context) {
    final isSuperEffective = typeMultiplier > 1;
    // 相性の倍率は 0.5・2 の積 (0.25〜) のため、% の整数にしても桁は落ちない
    final multiplierText = formatPowerPercent(
      powerPercent: (typeMultiplier * 100).round(),
    );
    return Semantics(
      label: isSuperEffective
          ? context.l10n.moveTypeSuperEffective(multiplierText)
          : context.l10n.moveTypeNotVeryEffective(multiplierText),
      child: ExcludeSemantics(
        child: Container(
          width: ElementTypeIcon.diameter,
          height: ElementTypeIcon.diameter,
          decoration: BoxDecoration(
            color: isSuperEffective
                ? SnapmonColors.accent
                : SnapmonColors.cardTrack,
            shape: BoxShape.circle,
          ),
          // 2 重の矢印は属性のアイコンより線が細く見えるため、丸 18 の中で 14 にして同じ重さに見せる
          child: Icon(
            isSuperEffective
                ? Icons.keyboard_double_arrow_up
                : Icons.keyboard_double_arrow_down,
            key: const Key('move-type-effectiveness'),
            size: 14,
            color: isSuperEffective
                ? SnapmonColors.textOnCard
                : SnapmonColors.textOnCardMuted,
          ),
        ),
      ),
    );
  }
}
