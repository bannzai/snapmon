/// 技の分類。
enum MoveCategory {
  /// 相手に威力に応じたダメージを与える技。
  attack,

  /// ダメージを与えない技。効果の仕様は未定のため、master の版 1 には含めていない。
  support,
}

/// 技の特殊効果の種類。自分・相手のメタ情報から威力の倍率を決める計算の一覧で、
/// 計算と説明文は lib/domain/battle/move_special_effect.dart の `calculateMoveSpecialEffect` が持つ。
enum MoveSpecialEffectKind {
  /// 相手の HP が減っているほど威力が上がる。
  opponentHitPointsLow,

  /// 自分の HP が減っているほど威力が上がる。
  ownHitPointsLow,

  /// 相手の防御が自分の攻撃より高い時に威力が上がる。
  tougherOpponent,

  /// この技の残り PP が少ないほど威力が上がる。
  powerPointsLow,

  /// 自分と相手が同じ属性を 1 つ以上持つ時に威力が上がる。
  sameElementAsOpponent,

  /// 自分と相手が同じ属性を 1 つも持たない時に威力が上がる。
  differentElementFromOpponent,

  /// そのターンに相手より先に行動した時に威力が上がる。
  movesFirst,

  /// そのターンに相手より後に行動した時に威力が上がる。
  movesLast,
}

/// 技の特殊効果。master の技の `specialEffect` の形 (見た目のエフェクト `effectId` とは別物)。
class MoveSpecialEffect {
  /// 特殊効果を作る。
  const MoveSpecialEffect({
    required this.kind,
    required this.maximumPowerPercent,
  });

  /// 効果の種類。
  final MoveSpecialEffectKind kind;

  /// 威力の倍率の最大 (%)。条件で決まる種類は条件を満たした時の倍率、割合で決まる種類は割合が最大の時の倍率。
  final int maximumPowerPercent;
}

/// [json] (master の技の `specialEffect`) から特殊効果を読む。null か、この版のアプリが知らない種類なら null を返す。
/// 知らない種類を無視するのは、新しい種類を足した master の版を古いアプリが読んでも、master 全体を読めなくしないため
/// (バトルは 1 台の端末で計算が閉じるため、端末ごとに効く効果が違っても対戦の結果は食い違わない)。
MoveSpecialEffect? moveSpecialEffectFromJson({
  required Map<String, dynamic>? json,
}) {
  if (json == null) {
    return null;
  }
  final kind = MoveSpecialEffectKind.values.asNameMap()[json['kind'] as String];
  return kind == null
      ? null
      : MoveSpecialEffect(
          kind: kind,
          maximumPowerPercent: json['maximumPowerPercent'] as int,
        );
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
    required this.specialEffect,
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
    specialEffect: moveSpecialEffectFromJson(
      json: json['specialEffect'] as Map<String, dynamic>?,
    ),
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

  /// 技の特殊効果。無い技は null。master の版をまたいで変えてよい値で、バトルは対戦時点の最新の版の効果を使う
  /// (documents/game-rules.md「技」)。
  final MoveSpecialEffect? specialEffect;
}
