import 'monster_stats.dart';

/// モンスターが覚える技の 1 件と、その技が使えるようになるレベル。
class LearnsetEntry {
  /// 覚える技の 1 件を作る。
  const LearnsetEntry({required this.moveId, required this.unlockLevel});

  /// 覚える技の識別子 (master かその場で作った定義の技の `id`)。
  final String moveId;

  /// この技が使えるようになるレベル。
  final int unlockLevel;
}

/// モンスターの生まれた時に決まる部分。生成後は変わらない
/// (変わる部分は `MonsterState`)。
class MonsterDefinition {
  /// モンスターの定義を作る。
  const MonsterDefinition({
    required this.id,
    required this.sourcePhotoReference,
    required this.name,
    required this.encyclopediaText,
    required this.elementTypeIds,
    required this.learnset,
    required this.baseStats,
    required this.individualValues,
    required this.statCalculationVersion,
    required this.masterVersion,
  });

  /// モンスターの一意な識別子。
  final String id;

  /// 元の写真の参照 (Cloud Storage のパス)。
  final String sourcePhotoReference;

  /// LLM が付けた名前。
  final String name;

  /// LLM が書いた図鑑の文章。
  final String encyclopediaText;

  /// 属性の識別子の一覧 (1 つ以上)。
  final List<String> elementTypeIds;

  /// 覚える技の一覧。レベルに応じて使える技が開放される。
  final List<LearnsetEntry> learnset;

  /// 種族値。Jev が判定した段階から決まる。
  final MonsterStats baseStats;

  /// 個体値。保存した説明文のハッシュを seed にして決まる。
  final MonsterStats individualValues;

  /// ステータスの計算手順の版。後で式を変えても、この版の式で計算し続ける。
  final int statCalculationVersion;

  /// 判定に使った master の版。
  final int masterVersion;
}
