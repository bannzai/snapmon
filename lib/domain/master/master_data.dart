import 'element_type.dart';
import 'move.dart';
import 'move_effect.dart';

/// ステータスの段階 (Jev の Score の答え) と、その段階に対応する種族値。
class StatGrade {
  /// 段階を作る。
  const StatGrade({
    required this.id,
    required this.displayName,
    required this.baseStat,
  });

  /// master の `statGrades` の要素から段階を読む。
  factory StatGrade.fromJson({required Map<String, dynamic> json}) => StatGrade(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    baseStat: json['baseStat'] as int,
  );

  /// 段階の識別子。Jev の Score の選択肢の名前と同じにする。
  final String id;

  /// 画面・文書に出す段階の名前。
  final String displayName;

  /// この段階に判定されたステータスの種族値。
  final int baseStat;
}

/// Jev の属性ごとの当てはまりの確率から、モンスターの属性を選ぶ規則。
class ElementSelectionRule {
  /// 規則を作る。
  const ElementSelectionRule({
    required this.probabilityThreshold,
    required this.maximumCount,
  });

  /// master の `elementSelection` から規則を読む。
  factory ElementSelectionRule.fromJson({required Map<String, dynamic> json}) =>
      ElementSelectionRule(
        probabilityThreshold: (json['probabilityThreshold'] as num).toDouble(),
        maximumCount: json['maximumCount'] as int,
      );

  /// この確率以上の属性だけを候補にする。
  final double probabilityThreshold;

  /// 1 体が持つ属性の数の上限。
  final int maximumCount;
}

/// 属性・相性表・技・エフェクト・ステータスの段階をまとめた定義の集まり。
/// master の元の JSON (`assets/master/master.json`。アプリには同梱せず、Firestore の `master/{version}` に
/// 置いたものをクライアントが取得する。ADR 0001「master に無い属性・技」) と、登録時にその場で作って
/// Firestore に保存した定義 (`definitions/`) が同じ形の JSON を持ち、どちらも [MasterData.fromJson] で読む。
class MasterData {
  /// 定義の集まりを作る。
  const MasterData({
    required this.version,
    required this.elementTypes,
    required this.typeChart,
    required this.moves,
    required this.effects,
    required this.statGrades,
    required this.elementSelection,
  });

  /// JSON から定義の集まりを読む。Firestore に保存したその場で作った定義は
  /// `typeChart` (新しい属性の相性は等倍に固定)・`effects`・`statGrades`・`elementSelection` を
  /// 持たないことがあるため、どれも省略できる。
  factory MasterData.fromJson({required Map<String, dynamic> json}) =>
      MasterData(
        version: json['version'] as int,
        elementTypes: [
          for (final elementTypeJson in json['elementTypes'] as List<dynamic>)
            ElementType.fromJson(json: elementTypeJson as Map<String, dynamic>),
        ],
        typeChart: {
          for (final attackerEntry
              in (json['typeChart'] as Map<String, dynamic>? ?? {}).entries)
            attackerEntry.key: {
              for (final defenderEntry
                  in (attackerEntry.value as Map<String, dynamic>).entries)
                defenderEntry.key: (defenderEntry.value as num).toDouble(),
            },
        },
        moves: [
          for (final moveJson in json['moves'] as List<dynamic>)
            Move.fromJson(json: moveJson as Map<String, dynamic>),
        ],
        effects: [
          for (final effectJson in json['effects'] as List<dynamic>? ?? [])
            MoveEffect.fromJson(json: effectJson as Map<String, dynamic>),
        ],
        statGrades: [
          for (final statGradeJson
              in json['statGrades'] as List<dynamic>? ?? [])
            StatGrade.fromJson(json: statGradeJson as Map<String, dynamic>),
        ],
        elementSelection: json['elementSelection'] == null
            ? null
            : ElementSelectionRule.fromJson(
                json: json['elementSelection'] as Map<String, dynamic>,
              ),
      );

  /// 定義の版。モンスターは判定に使った master の版を保存する。
  /// 版を上げても既存の属性・技・エフェクトの ID の値は変えない (変えるのは相性表と、新しい ID の追加だけ。
  /// documents/game-rules.md「技」)。そのためバトルは最新の版 1 つから全員の技を引ける。
  final int version;

  /// 属性の一覧。
  final List<ElementType> elementTypes;

  /// 相性表。`typeChart[攻撃側の属性 ID][防御側の属性 ID]` が倍率 (0.5 / 1 / 2)。
  final Map<String, Map<String, double>> typeChart;

  /// 技の一覧。
  final List<Move> moves;

  /// 技のエフェクトの一覧。
  final List<MoveEffect> effects;

  /// ステータスの段階と種族値の対応。
  final List<StatGrade> statGrades;

  /// 属性を選ぶ規則。その場で作った定義には無い。
  final ElementSelectionRule? elementSelection;

  /// [moveId] の技を返す。無ければ [StateError] を投げる。
  Move moveById({required String moveId}) => moves.firstWhere(
    (move) => move.id == moveId,
    orElse: () => throw StateError('技 $moveId が定義に無い'),
  );

  /// 攻撃側の属性 [attackerElementTypeId] から防御側の属性 [defenderElementTypeId] への倍率を返す。
  double typeMultiplier({
    required String attackerElementTypeId,
    required String defenderElementTypeId,
  }) =>
      typeChart[attackerElementTypeId]?[defenderElementTypeId] ??
      // その場で作った属性の相性は、既存の全属性と等倍を既定にする (ADR 0001「master に無い属性・技」)。
      // master 自体の組の抜けはテスト (test/domain/master/master_data_test.dart) で防ぐ。
      1;
}

/// master [base] に、その場で作った定義 [additional] を足した定義の集まりを返す。
/// 版・相性表・ステータスの段階・属性を選ぶ規則は [base] のものを使う。
/// 同じ ID の定義が両方にある時は [base] を優先する (master の定義を上書きさせないため)。
MasterData mergeMasterData({
  required MasterData base,
  required MasterData additional,
}) {
  final baseElementTypeIds = {
    for (final elementType in base.elementTypes) elementType.id,
  };
  final baseMoveIds = {for (final move in base.moves) move.id};
  final baseEffectIds = {for (final effect in base.effects) effect.id};
  return MasterData(
    version: base.version,
    elementTypes: [
      ...base.elementTypes,
      ...additional.elementTypes.where(
        (elementType) => !baseElementTypeIds.contains(elementType.id),
      ),
    ],
    // その場で作った属性の相性は等倍に固定するため (ADR 0001「master に無い属性・技」)、
    // [additional] が相性表を持っていても取り込まず、[typeMultiplier] の等倍の既定に任せる。
    typeChart: base.typeChart,
    moves: [
      ...base.moves,
      ...additional.moves.where((move) => !baseMoveIds.contains(move.id)),
    ],
    effects: [
      ...base.effects,
      ...additional.effects.where(
        (effect) => !baseEffectIds.contains(effect.id),
      ),
    ],
    statGrades: base.statGrades,
    elementSelection: base.elementSelection,
  );
}
