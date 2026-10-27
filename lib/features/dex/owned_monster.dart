import '../../domain/monster/monster_decoration.dart';
import '../../domain/monster/monster_definition.dart';

/// 図鑑に入っている 1 体。生まれた時に決まる部分と、保存して変わる部分 (レベル) の組。
/// サーバーの図鑑は Firestore の `users/{uid}/monsters/{monsterId}` (形は functions/src/generation/records.ts の
/// `MonsterDocument`) から、PvP の相手は fetchOpponents の応答 (形は functions/src/pvp_rules.ts の `PublicMonster`) から読み、
/// 見本のモンスターは assets/samples/sample_monsters.json から読む。
class OwnedMonster {
  /// 図鑑の 1 体を作る。
  const OwnedMonster({
    required this.definition,
    required this.level,
    required this.artPath,
    required this.definitionIds,
    required this.decoration,
    required this.decorationVersion,
  });

  /// Firestore の `users/{uid}/monsters/{monsterId}` のドキュメントか fetchOpponents の応答のモンスター [json] から 1 体を読む。
  factory OwnedMonster.fromJson({required Map<String, dynamic> json}) {
    final decorationVersion = json['decorationVersion'] as int?;
    final decorationJson = json['decoration'] as Map<String, dynamic>?;
    return OwnedMonster(
      definition: MonsterDefinition.fromJson(
        json: json['definition'] as Map<String, dynamic>,
      ),
      level: json['level'] as int,
      artPath: json['artPath'] as String,
      definitionIds: [
        for (final definitionId in json['definitionIds'] as List<dynamic>)
          definitionId as String,
      ],
      decoration:
          decorationJson == null ||
              !supportedDecorationVersions.contains(decorationVersion)
          ? null
          : MonsterDecoration.fromJson(json: decorationJson),
      decorationVersion: decorationVersion,
    );
  }

  /// 生まれた時に決まる部分。
  final MonsterDefinition definition;

  /// 今のレベル。
  final int level;

  /// 写真から切り出した被写体の画像の Storage のパス (`monsters/{monsterId}/art.png`)。
  /// 見本のモンスターは切り出した画像を持たず null で、仮の絵を描く。
  final String? artPath;

  /// 参照するその場で作った属性・技の定義 (`definitions/{definitionId}`) の ID。見本のモンスターは空。
  final List<String> definitionIds;

  /// 切り出した画像に重ねる装飾のパラメータ。見本のモンスターと、[decorationVersion] がこのクライアントの描けない版の時は null。
  final MonsterDecoration? decoration;

  /// 装飾の描画の版 (生まれた時の見た目を変えないため、版ごとに描き分ける)。見本のモンスターは null。
  final int? decorationVersion;
}
