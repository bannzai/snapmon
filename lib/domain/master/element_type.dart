/// 属性の定義。master (`assets/master/master.json`) の `elementTypes` と、
/// 登録時にその場で作って Firestore に保存した定義が同じ形を持つ。
class ElementType {
  /// 属性の定義を作る。
  const ElementType({required this.id, required this.displayName});

  /// JSON (master と Firestore の定義に共通の形) から属性を読む。
  factory ElementType.fromJson({required Map<String, dynamic> json}) =>
      ElementType(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
      );

  /// 属性の一意な識別子。相性表・技・モンスターから参照される。
  final String id;

  /// 画面に出す属性の名前。
  final String displayName;
}
