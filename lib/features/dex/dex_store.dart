import 'package:flutter/foundation.dart';

import '../../domain/battle/battle_state.dart';
import 'owned_monster.dart';

/// 図鑑と手持ちの状態。Firestore に繋ぐ (#14) までは端末のメモリだけに持ち、アプリを閉じると消える。
class DexStore extends ChangeNotifier {
  final List<OwnedMonster> _monsters = [];
  final List<String> _partyMonsterIds = [];

  /// 図鑑のモンスター (入った順)。
  List<OwnedMonster> get monsters => List.unmodifiable(_monsters);

  /// 手持ちのモンスター (最大 [maximumPartySize] 体、入れた順)。
  List<OwnedMonster> get party => [
    for (final monsterId in _partyMonsterIds)
      _monsters.firstWhere((monster) => monster.definition.id == monsterId),
  ];

  /// [monsterId] のモンスターが図鑑にいるか。
  bool contains({required String monsterId}) =>
      _monsters.any((monster) => monster.definition.id == monsterId);

  /// [monsterId] のモンスターが手持ちにいるか。
  bool isInParty({required String monsterId}) =>
      _partyMonsterIds.contains(monsterId);

  /// 手持ちに空きがあるか。
  bool get hasPartyVacancy => _partyMonsterIds.length < maximumPartySize;

  /// [monster] を図鑑に入れる。同じ識別子のモンスターがいれば何もしない (同じ被写体を二重に登録しないため)。
  void addMonster({required OwnedMonster monster}) {
    if (contains(monsterId: monster.definition.id)) {
      return;
    }
    _monsters.add(monster);
    notifyListeners();
  }

  /// 図鑑にいる [monsterId] のモンスターを手持ちに入れる。
  /// 既に手持ちにいる・手持ちに空きが無い・図鑑にいない時は何もしない。
  void addToParty({required String monsterId}) {
    if (isInParty(monsterId: monsterId) ||
        !hasPartyVacancy ||
        !contains(monsterId: monsterId)) {
      return;
    }
    _partyMonsterIds.add(monsterId);
    notifyListeners();
  }

  /// [monsterId] のモンスターを手持ちから外す。手持ちにいない時は何もしない。
  void removeFromParty({required String monsterId}) {
    if (_partyMonsterIds.remove(monsterId)) {
      notifyListeners();
    }
  }

  /// 図鑑を [monsters] だけにし、先頭から [maximumPartySize] 体を手持ちにする (開発者メニューの見本の投入)。
  void replaceAll({required List<OwnedMonster> monsters}) {
    _monsters
      ..clear()
      ..addAll(monsters);
    _partyMonsterIds
      ..clear()
      ..addAll(
        monsters.take(maximumPartySize).map((monster) => monster.definition.id),
      );
    notifyListeners();
  }

  /// 図鑑と手持ちを空にする。
  void clear() => replaceAll(monsters: const []);
}
