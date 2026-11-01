import 'package:flutter/material.dart';

import '../features/opponent/pvp_client.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_text_styles.dart';
import 'storage_image.dart';

/// トレーナー [profile] のアイコンを一辺 [dimension] の角丸の正方形で描く。
/// アイコンを登録していない (CPU トレーナーを含む) 時と読む前・読めなかった時は、既定の印 (表示名の最初の 1 文字) を描く。
class TrainerIcon extends StatelessWidget {
  /// [profile] のアイコンを作る。
  const TrainerIcon({
    super.key,
    required this.profile,
    required this.dimension,
  });

  /// 描くトレーナー。
  final TrainerProfile profile;

  /// 一辺の論理 px。
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final iconPath = profile.iconPath;
    final defaultMark = ColoredBox(
      color: SnapmonColors.artBackground,
      child: Center(
        child: Text(
          // 表示名は Functions が必ず決めて返す (設定していなければ「トレーナー」+ 4 桁) が、空の名前を受け取っても落ちないよう、印を描かずに地だけ出す
          profile.displayName.characters.firstOrNull ?? '',
          // 印の文字は一辺の半分の大きさにし、どの大きさのアイコンでも枠に対して同じ割合で見せる
          style: SnapmonTextStyles.cardTitle.copyWith(
            color: SnapmonColors.accent,
            fontSize: dimension / 2,
            height: 1,
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: dimension,
      child: ClipRRect(
        // 角丸は一辺の 1/4 にし、小さいアイコンでも大きいアイコンでも同じ形に見せる (DIRECTION.md「デザインの方向」の大きめの角丸)
        borderRadius: BorderRadius.circular(dimension / 4),
        child: iconPath == null
            ? defaultMark
            : StorageImage(
                key: ValueKey(iconPath),
                storagePath: iconPath,
                fit: BoxFit.cover,
                placeholder: defaultMark,
              ),
      ),
    );
  }
}

/// トレーナー [profile] のアイコンと表示名を横に並べた札。対戦タブと対戦画面で、戦うトレーナーを示す。
class TrainerLabel extends StatelessWidget {
  /// [profile] の札を作る。
  const TrainerLabel({super.key, required this.profile});

  /// 示すトレーナー。
  final TrainerProfile profile;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TrainerIcon(profile: profile, dimension: 28),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          profile.displayName,
          style: SnapmonTextStyles.label,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
