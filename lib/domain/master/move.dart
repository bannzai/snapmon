/// 技の分類。
enum MoveCategory {
  /// 相手に威力に応じたダメージを与える技。
  attack,

  /// ダメージを与えない技。効果の仕様は未定のため、master の版 1 には含めていない。
  support,
}

/// 技の定義。master (`assets/master/master.json`) の `moves` と、
/// 登録時にその場で作って Firestore に保存した定義が同じ形を持つ。
class Move {
  /// 技の定義を作る。
  const Move({
    required this.id,
    required this.displayName,
    required this.elementTypeId,
    required this.power,
    required this.powerPoints,
    required this.category,
    required this.effectId,
    required this.learnableLevelMinimum,
    required this.learnableLevelMaximum,
  });

  /// JSON (master と Firestore の定義に共通の形) から技を読む。
  factory Move.fromJson({required Map<String, dynamic> json}) => Move(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    elementTypeId: json['elementTypeId'] as String,
    power: json['power'] as int,
    powerPoints: json['powerPoints'] as int,
    category: MoveCategory.values.byName(json['category'] as String),
    effectId: json['effectId'] as String,
    learnableLevelMinimum: json['learnableLevelMinimum'] as int,
    learnableLevelMaximum: json['learnableLevelMaximum'] as int,
  );

  /// 技の一意な識別子。
  final String id;

  /// 画面に出す技の名前。
  final String displayName;

  /// 技の属性 (1 つ)。相性表の攻撃側として引く。
  final String elementTypeId;

  /// ダメージ式に入る威力。
  final int power;

  /// 1 回のバトルで使える回数の上限 (PP)。
  final int powerPoints;

  /// 技の分類。
  final MoveCategory category;

  /// 技を使った時に出すエフェクトの識別子 (`effects` の `id`)。
  final String effectId;

  /// 生成時にモンスターへ覚えさせてよいレベル帯の下限。
  final int learnableLevelMinimum;

  /// 生成時にモンスターへ覚えさせてよいレベル帯の上限。
  final int learnableLevelMaximum;
}
