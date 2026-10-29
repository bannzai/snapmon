/// 装飾の目の形。値の名前は functions/src/generation/prompts/describe_subject.ts の `EYE_STYLES` と同じ。
enum MonsterEyeStyle { round, sleepy, sharp, sparkle, dot }

/// 装飾の口の形。値の名前は `MOUTH_STYLES` と同じ。
enum MonsterMouthStyle { smile, open, fang, flat, none }

/// 装飾の手足の形。値の名前は `LIMB_STYLES` と同じ。
enum MonsterLimbStyle { none, stubby, long, wings, tentacles }

/// 装飾の属性のオーラの形。値の名前は `AURA_STYLES` と同じ。色は属性から決める。
enum MonsterAuraStyle { soft, flame, spark, bubble, leaf }

/// クライアントが読める装飾の描画の版 (functions の `DECORATION_VERSION`)。
/// これに無い版のモンスターは装飾を読まない (新しい版の形を古いクライアントが読み違えないため)。
const Set<int> supportedDecorationVersions = {1};

/// 生成の時に Claude が決め、モンスターと一緒に保存される装飾のパラメータ
/// (形は functions/src/generation/prompts/describe_subject.ts の `MonsterDecoration`)。
/// 絵には描かない (DIRECTION.md「決めたこと」2026-10-29)。
class MonsterDecoration {
  /// 装飾のパラメータを作る。
  const MonsterDecoration({
    required this.eyeStyle,
    required this.mouthStyle,
    required this.limbStyle,
    required this.auraStyle,
    required this.eyeCenterX,
    required this.eyeCenterY,
    required this.eyeScale,
    required this.outlineColorHex,
  });

  /// JSON (フィールド名はこのクラスのプロパティ名と同じ) から装飾のパラメータを読む。
  /// 割合は範囲の端で整数 (0・1) として届くことがあるため num で読む。
  factory MonsterDecoration.fromJson({required Map<String, dynamic> json}) =>
      MonsterDecoration(
        eyeStyle: MonsterEyeStyle.values.byName(json['eyeStyle'] as String),
        mouthStyle: MonsterMouthStyle.values.byName(
          json['mouthStyle'] as String,
        ),
        limbStyle: MonsterLimbStyle.values.byName(json['limbStyle'] as String),
        auraStyle: MonsterAuraStyle.values.byName(json['auraStyle'] as String),
        eyeCenterX: (json['eyeCenterX'] as num).toDouble(),
        eyeCenterY: (json['eyeCenterY'] as num).toDouble(),
        eyeScale: (json['eyeScale'] as num).toDouble(),
        outlineColorHex: _validOutlineColorHex(
          outlineColorHex: json['outlineColorHex'] as String,
        ),
      );

  /// [outlineColorHex] が `#RRGGBB` (functions/src/generation/prompts/describe_subject.ts の検査と同じ形) ならそのまま返し、違えば FormatException を投げる。
  /// 描く時に色を読めずに例外になるのを避け、読む時に失敗させて装飾無しに倒すため。
  static String _validOutlineColorHex({required String outlineColorHex}) =>
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(outlineColorHex)
      ? outlineColorHex
      : throw FormatException('outlineColorHex', outlineColorHex);

  /// 目の形。
  final MonsterEyeStyle eyeStyle;

  /// 口の形。
  final MonsterMouthStyle mouthStyle;

  /// 手足の形。
  final MonsterLimbStyle limbStyle;

  /// 属性のオーラの形。
  final MonsterAuraStyle auraStyle;

  /// 両目の中心の横位置 (切り出した画像の幅に対する 0〜1)。
  final double eyeCenterX;

  /// 両目の中心の縦位置 (切り出した画像の高さに対する 0〜1)。
  final double eyeCenterY;

  /// 目の大きさ (被写体の幅に対する割合)。
  final double eyeScale;

  /// 輪郭線の色 (#RRGGBB)。
  final String outlineColorHex;
}
