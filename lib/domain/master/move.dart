import '../monster/monster_stats.dart';

/// 技の分類。
enum MoveCategory {
  /// 相手に威力に応じたダメージを与える技。
  attack,

  /// ダメージを与えず (威力 0)、特殊効果でステータスを変えるか HP を回復する技 (master の版 7。#181)。
  support,
}

/// 補助技の効果で変えられるステータス。HP は回復 ([MoveSpecialEffect.selfHitPointsRecovery]) で変え、ここには入れない。
const modifiableStatKinds = [StatKind.attack, StatKind.defense, StatKind.speed];

/// 技の特殊効果。master の技の `specialEffect` の形 (見た目のエフェクト `effectId` とは別物)。
/// 効果は式 (lib/domain/battle/move_expression.dart。文法は documents/game-rules.md「技の式」) で書き、
/// 出力ごとに 1 つの式を持つ。攻撃技は威力の倍率 ([power])、補助技はステータスの変化と回復を持つ。
class MoveSpecialEffect {
  /// 特殊効果を作る。
  const MoveSpecialEffect({
    required this.power,
    required this.selfStatChanges,
    required this.opponentStatChanges,
    required this.selfHitPointsRecovery,
    required this.summary,
    required this.rule,
  });

  /// 威力の倍率 (%。100 が 1 倍) を返す式。無い効果は null。評価できない時は 100 にする
  /// (lib/domain/battle/move_special_effect.dart の `calculateMoveSpecialEffect`)。
  final String? power;

  /// 技を使う側のステータスの倍率 (%) に足す値を返す式。キーは [modifiableStatKinds] のどれか。
  final Map<StatKind, String> selfStatChanges;

  /// 相手のステータスの倍率 (%) に足す値を返す式。キーは [modifiableStatKinds] のどれか。
  final Map<StatKind, String> opponentStatChanges;

  /// 技を使う側の HP を回復する量を返す式。無い効果は null。
  final String? selfHitPointsRecovery;

  /// 技の枠に出す、効果の短い説明。
  final String summary;

  /// バトルのログと技の詳細の画面に出す、効果の規則の説明 (例: 先に行動すると威力が上がる)。
  final String rule;
}

/// [json] (master の技の `specialEffect`) から特殊効果を読む。null か、式を 1 つも持たない形 (master の版 4 までの
/// `kind` の形) なら null を返す。古い形で throw しないのは、版 5 を投入する前の最新の版 (版 4) を新しいアプリが読んでも
/// master 全体を読めなくしないため。ステータスの変化のキーが変えられるステータス ([modifiableStatKinds]) に無い出力は読まない
/// (式の評価できない時と同じく効果を無いものにするため)。
MoveSpecialEffect? moveSpecialEffectFromJson({
  required Map<String, dynamic>? json,
}) {
  if (json case {'summary': final String summary, 'rule': final String rule}) {
    Map<StatKind, String> statChangesOf({required Object? statChangesJson}) => {
      if (statChangesJson case final Map<String, dynamic> changes)
        for (final statKind in modifiableStatKinds)
          if (changes[statKind.name] case final String expression)
            statKind: expression,
    };
    final specialEffect = MoveSpecialEffect(
      power: json['power'] as String?,
      selfStatChanges: statChangesOf(statChangesJson: json['selfStatChanges']),
      opponentStatChanges: statChangesOf(
        statChangesJson: json['opponentStatChanges'],
      ),
      selfHitPointsRecovery: json['selfHitPointsRecovery'] as String?,
      summary: summary,
      rule: rule,
    );
    return specialEffect.power == null &&
            specialEffect.selfStatChanges.isEmpty &&
            specialEffect.opponentStatChanges.isEmpty &&
            specialEffect.selfHitPointsRecovery == null
        ? null
        : specialEffect;
  }
  return null;
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
  /// 技と特殊効果の `rationale` (根拠) は保守のための値でユーザーに見せないため読まない (documents/game-rules.md「技の根拠」)。
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
