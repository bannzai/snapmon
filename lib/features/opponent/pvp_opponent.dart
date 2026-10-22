import '../dex/owned_monster.dart';

/// 非同期 PvP の相手 1 人。Functions の fetchOpponents が返す 1 件 (functions/src/pvp.ts) の形。
/// DEBUG ビルドでログインを飛ばした時は、見本の対戦相手をこの形にして代わりに出す。
class PvpOpponent {
  /// 相手 1 人を作る。
  const PvpOpponent({
    required this.opponentUid,
    required this.displayName,
    required this.monsters,
  });

  /// fetchOpponents が返す 1 件 [json] から相手を読む。
  /// モンスターは他人に見せてよい項目だけで、元の写真の参照を持たない (`MonsterDefinition.sourcePhotoReference` は null)。
  factory PvpOpponent.fromJson({required Map<String, dynamic> json}) =>
      PvpOpponent(
        opponentUid: json['opponentUid'] as String,
        displayName: json['displayName'] as String,
        monsters: [
          for (final monsterJson in json['monsters'] as List<dynamic>)
            OwnedMonster.fromJson(json: monsterJson as Map<String, dynamic>),
        ],
      );

  /// 相手の uid (通報・ブロックの宛先)。見本の相手では見本の対戦相手の識別子。
  final String opponentUid;

  /// 相手の表示名。
  final String displayName;

  /// 相手の手持ち (1〜3 体。レベルは相手の今のレベル)。
  final List<OwnedMonster> monsters;
}
