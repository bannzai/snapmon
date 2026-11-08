/// 技のエフェクトの定義。master (`assets/master/master.json`) の `effects` と、
/// 登録時にその場で作って Firestore に保存した定義が同じ形を持つ。
/// 描画は画面側 (Flame) が行い、[spriteSheet] のシート (lib/features/battle/move_effect_sprite_sheets.dart) が
/// 無いか読めなければ `colorHex` の色のパーティクルで描く。
class MoveEffect {
  /// エフェクトの定義を作る。
  const MoveEffect({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.colorHex,
    this.spriteSheet,
  });

  /// JSON (master と Firestore の定義に共通の形) からエフェクトを読む。`spriteSheet` は版 8 までの定義に無く、無ければ null。
  factory MoveEffect.fromJson({required Map<String, dynamic> json}) =>
      MoveEffect(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        kind: json['kind'] as String,
        colorHex: json['colorHex'] as String,
        spriteSheet: json['spriteSheet'] as String?,
      );

  /// エフェクトの一意な識別子。技の `effectId` から参照される。
  final String id;

  /// 開発者向けのエフェクトの名前。
  final String displayName;

  /// エフェクトの作り方 (`particle`・`spriteSheet`)。
  final String kind;

  /// エフェクトの主色 (`#RRGGBB`)。
  final String colorHex;

  /// スプライトシートで描くエフェクトのシートの名前 (`assets/images/move_effects/` のファイル名、拡張子なし)。パーティクルで描くエフェクトは null。
  final String? spriteSheet;
}
