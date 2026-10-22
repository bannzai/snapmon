import '../../domain/monster/monster_definition.dart';

/// 図鑑に入っている 1 体。生まれた時に決まる部分と、保存して変わる部分 (レベル) の組。
/// Firestore の `users/{uid}/monsters` に繋ぐ (#14) までは端末のメモリだけに持つ。
class OwnedMonster {
  /// 図鑑の 1 体を作る。
  const OwnedMonster({required this.definition, required this.level});

  /// 生まれた時に決まる部分。
  final MonsterDefinition definition;

  /// 今のレベル。
  final int level;
}
