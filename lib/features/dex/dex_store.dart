import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import 'owned_monster.dart';

/// 図鑑と手持ちの状態と、図鑑のモンスターが参照する属性・技の定義。
/// ログインした後は Firestore の `users/{uid}/monsters`・`users/{uid}/party/current` を反映し
/// (lib/firebase/dex_firestore.dart が [applyServerSnapshot] を呼ぶ)、手持ちの変更を [connectServer] で渡された関数で保存する。
/// サーバーに繋ぐまで (DEBUG ビルドでログインを飛ばした時) は端末のメモリだけに持ち、アプリを閉じると消える。
class DexStore extends ChangeNotifier {
  /// 図鑑を作る。[definitions] はサーバーの定義を読むまでの定義 (見本のモンスターの属性・技を引けるもの)。
  DexStore({required MasterData definitions}) : _definitions = definitions;

  List<OwnedMonster> _monsters = [];
  List<String> _partyMonsterIds = [];
  MasterData _definitions;
  Future<void> Function({required List<String> monsterIds})?
  _savePartyMonsterIds;
  Future<void> Function()? _refreshDefinitions;
  Object? _serverError;

  /// 図鑑のモンスター (入った順)。
  List<OwnedMonster> get monsters => List.unmodifiable(_monsters);

  /// 手持ちのモンスター (最大 [maximumPartySize] 体、入れた順)。
  /// 手持ちの ID のうち図鑑にまだ届いていないモンスターは除く (Firestore の手持ちと図鑑は別々に届くため)。
  List<OwnedMonster> get party => [
    for (final monsterId in _partyMonsterIds)
      ..._monsters.where((monster) => monster.definition.id == monsterId),
  ];

  /// 図鑑のモンスターと対戦の相手の属性・技を引く定義。
  MasterData get definitions => _definitions;

  /// サーバーの図鑑に繋いでいるか ([connectServer] の後か)。
  bool get isServerBacked => _savePartyMonsterIds != null;

  /// サーバーの図鑑の読み込みの最後の失敗。成功した時は null。
  Object? get serverError => _serverError;

  /// [monsterId] のモンスターが図鑑にいるか。
  bool contains({required String monsterId}) =>
      _monsters.any((monster) => monster.definition.id == monsterId);

  /// [monsterId] のモンスターが手持ちにいるか。
  bool isInParty({required String monsterId}) =>
      _partyMonsterIds.contains(monsterId);

  /// 手持ちに空きがあるか。図鑑にまだ届いていない手持ちも数える (届く前に入れて、保存した手持ちから外さないため)。
  bool get hasPartyVacancy => _partyMonsterIds.length < maximumPartySize;

  /// 手持ちの変更を保存している途中か。途中は次の変更を受け付けない ([addToParty] 等が [StateError] を投げる)。
  bool get isSavingParty => _isSavingParty;
  bool _isSavingParty = false;

  /// サーバーの図鑑に繋ぐ。以後の手持ちの変更は [savePartyMonsterIds] で保存し、[refreshDefinitions] で定義を
  /// サーバーの最新の master から読み直す。何度呼んでも最後の関数を使う。
  void connectServer({
    required Future<void> Function({required List<String> monsterIds})
    savePartyMonsterIds,
    required Future<void> Function() refreshDefinitions,
  }) {
    _savePartyMonsterIds = savePartyMonsterIds;
    _refreshDefinitions = refreshDefinitions;
    notifyListeners();
  }

  /// サーバーの図鑑に繋いでいる時は、定義を最新の master から読み直す (対戦の前。相性表は対戦時点の最新の版を両者に適用するため。
  /// documents/adr/0001-tech-stack.md)。繋いでいない時は何もしない。読み直しに失敗した時は例外を投げる。
  Future<void> refreshDefinitions() async => _refreshDefinitions?.call();

  /// サーバーの図鑑から離れ、空の端末の図鑑 (定義は [definitions]) に戻す (ログインを終えた時。別の uid の図鑑を残さないため)。
  void disconnectServer({required MasterData definitions}) {
    _savePartyMonsterIds = null;
    _refreshDefinitions = null;
    _definitions = definitions;
    _monsters = [];
    _partyMonsterIds = [];
    _serverError = null;
    notifyListeners();
  }

  /// サーバーから届いた図鑑 [monsters]・手持ち [partyMonsterIds]・定義 [definitions] を反映する。null の項目は変えない。
  void applyServerSnapshot({
    required List<OwnedMonster>? monsters,
    required List<String>? partyMonsterIds,
    required MasterData? definitions,
  }) {
    if (definitions != null) {
      _definitions = definitions;
    }
    if (monsters != null) {
      _monsters = List.of(monsters);
    }
    if (partyMonsterIds != null) {
      _partyMonsterIds = List.of(partyMonsterIds);
    }
    _serverError = null;
    notifyListeners();
  }

  /// サーバーの図鑑の読み込みの失敗 [error] を残す (図鑑の画面に出す)。
  void reportServerError({required Object error}) {
    _serverError = error;
    notifyListeners();
  }

  /// [monsterId] のモンスターが図鑑に届いたら、そのモンスターを返す (生成の直後は Firestore の図鑑の反映を待つため)。
  /// [timeout] までに届かなければ [TimeoutException] を投げる。
  Future<OwnedMonster> waitForMonster({
    required String monsterId,
    required Duration timeout,
  }) {
    OwnedMonster? findMonster() => _monsters
        .where((monster) => monster.definition.id == monsterId)
        .firstOrNull;
    final found = findMonster();
    if (found != null) {
      return Future.value(found);
    }
    final completer = Completer<OwnedMonster>();
    void onChanged() {
      final monster = findMonster();
      if (monster != null && !completer.isCompleted) {
        completer.complete(monster);
      }
    }

    addListener(onChanged);
    return completer.future
        .timeout(
          timeout,
          onTimeout: () =>
              throw TimeoutException('モンスター $monsterId が図鑑に届きませんでした', timeout),
        )
        .whenComplete(() => removeListener(onChanged));
  }

  /// 図鑑にいる [monsterId] のモンスターを手持ちに入れる。
  /// 既に手持ちにいる・手持ちに空きが無い・図鑑にいない時は何もしない。保存に失敗した時は元に戻して例外を投げる。
  Future<void> addToParty({required String monsterId}) {
    if (isInParty(monsterId: monsterId) ||
        !hasPartyVacancy ||
        !contains(monsterId: monsterId)) {
      return Future.value();
    }
    return _changeParty(monsterIds: [..._partyMonsterIds, monsterId]);
  }

  /// 手持ちの [outgoingMonsterId] を、図鑑にいる [incomingMonsterId] と入れ替える (手持ちの中の位置は変えない)。
  /// [outgoingMonsterId] が手持ちにいない・[incomingMonsterId] が既に手持ちにいるか図鑑にいない時は何もしない。
  /// 保存に失敗した時は元に戻して例外を投げる。
  Future<void> replacePartyMember({
    required String outgoingMonsterId,
    required String incomingMonsterId,
  }) {
    if (!isInParty(monsterId: outgoingMonsterId) ||
        isInParty(monsterId: incomingMonsterId) ||
        !contains(monsterId: incomingMonsterId)) {
      return Future.value();
    }
    return _changeParty(
      monsterIds: [
        for (final monsterId in _partyMonsterIds)
          monsterId == outgoingMonsterId ? incomingMonsterId : monsterId,
      ],
    );
  }

  /// [monsterId] のモンスターを手持ちから外す。手持ちにいない時は何もしない。保存に失敗した時は元に戻して例外を投げる。
  Future<void> removeFromParty({required String monsterId}) {
    if (!isInParty(monsterId: monsterId)) {
      return Future.value();
    }
    return _changeParty(
      monsterIds: [
        for (final partyMonsterId in _partyMonsterIds)
          if (partyMonsterId != monsterId) partyMonsterId,
      ],
    );
  }

  /// 手持ちを [monsterIds] にして、サーバーに繋いでいれば保存する。
  /// 画面にはすぐ反映し、保存に失敗したら変更の前に戻して例外を投げる (Firestore の手持ちと食い違わせないため)。
  /// 保存の途中に呼ばれた時は変えずに [StateError] を投げる (並んだ保存の片方が失敗した時に、もう片方の変更まで
  /// 巻き戻して食い違わせないため)。
  Future<void> _changeParty({required List<String> monsterIds}) async {
    if (_isSavingParty) {
      throw StateError('手持ちを保存しています');
    }
    final previousPartyMonsterIds = _partyMonsterIds;
    _partyMonsterIds = monsterIds;
    _isSavingParty = true;
    notifyListeners();
    try {
      await _savePartyMonsterIds?.call(monsterIds: monsterIds);
    } catch (_) {
      _partyMonsterIds = previousPartyMonsterIds;
      rethrow;
    } finally {
      _isSavingParty = false;
      notifyListeners();
    }
  }

  /// 図鑑のモンスターのレベルを [levelsByMonsterId] (monsterId ごとのレベル) に置き換える。図鑑にいない ID は無視する。
  /// サーバーの図鑑では、Functions が保存したレベルが Firestore から届くまでの間の表示に使う。
  void updateLevels({required Map<String, int> levelsByMonsterId}) {
    _monsters = [
      for (final monster in _monsters)
        levelsByMonsterId[monster.definition.id] == null
            ? monster
            : OwnedMonster(
                definition: monster.definition,
                level: levelsByMonsterId[monster.definition.id]!,
                artPath: monster.artPath,
                definitionIds: monster.definitionIds,
              ),
    ];
    notifyListeners();
  }

  /// 図鑑を [monsters] だけにし、先頭から [maximumPartySize] 体を手持ちにする (開発者メニューの見本の投入)。
  /// サーバーの図鑑に繋いでいる時は使わない (見本のモンスターはサーバーに無く、手持ちを保存できないため)。
  void replaceAll({required List<OwnedMonster> monsters}) {
    _monsters = List.of(monsters);
    _partyMonsterIds = [
      for (final monster in monsters.take(maximumPartySize))
        monster.definition.id,
    ];
    notifyListeners();
  }

  /// 図鑑と手持ちを空にする。
  void clear() => replaceAll(monsters: const []);
}
