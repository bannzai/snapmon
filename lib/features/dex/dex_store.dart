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
  List<String> _partyMonsterIDs = [];
  MasterData _definitions;
  Future<void> Function({required List<String> monsterIDs})?
  _savePartyMonsterIDs;
  Future<void> Function()? _refreshDefinitions;
  Future<void> Function({
    required String monsterID,
    required List<String> moveIDs,
  })?
  _saveSelectedMoveIDs;
  Object? _serverError;

  /// 図鑑のモンスター (入った順)。
  List<OwnedMonster> get monsters => List.unmodifiable(_monsters);

  /// 手持ちのモンスター (最大 [maximumPartySize] 体、入れた順)。
  /// 手持ちの ID のうち図鑑にまだ届いていないモンスターは除く (Firestore の手持ちと図鑑は別々に届くため)。
  List<OwnedMonster> get party => [
    for (final monsterID in _partyMonsterIDs)
      ..._monsters.where((monster) => monster.definition.id == monsterID),
  ];

  /// 図鑑のモンスターと対戦の相手の属性・技を引く定義。
  MasterData get definitions => _definitions;

  /// サーバーの図鑑に繋いでいるか ([connectServer] の後か)。
  bool get isServerBacked => _savePartyMonsterIDs != null;

  /// サーバーの図鑑の読み込みの最後の失敗。成功した時は null。
  Object? get serverError => _serverError;

  /// [monsterID] のモンスターが図鑑にいるか。
  bool contains({required String monsterID}) =>
      _monsters.any((monster) => monster.definition.id == monsterID);

  /// [monsterID] のモンスターが手持ちにいるか。
  bool isInParty({required String monsterID}) =>
      _partyMonsterIDs.contains(monsterID);

  /// 手持ちに空きがあるか。図鑑にまだ届いていない手持ちも数える (届く前に入れて、保存した手持ちから外さないため)。
  bool get hasPartyVacancy => _partyMonsterIDs.length < maximumPartySize;

  /// 手持ちの変更を保存している途中か。途中は次の変更を受け付けない ([addToParty] 等が [StateError] を投げる)。
  bool get isSavingParty => _isSavingParty;
  bool _isSavingParty = false;

  /// サーバーの図鑑に繋ぐ。以後の手持ちの変更は [savePartyMonsterIDs] で、対戦の前に選んだ技は [saveSelectedMoveIDs] で保存し、
  /// [refreshDefinitions] で定義をサーバーの最新の master から読み直す。何度呼んでも最後の関数を使う。
  void connectServer({
    required Future<void> Function({required List<String> monsterIDs})
    savePartyMonsterIDs,
    required Future<void> Function({
      required String monsterID,
      required List<String> moveIDs,
    })
    saveSelectedMoveIDs,
    required Future<void> Function() refreshDefinitions,
  }) {
    _savePartyMonsterIDs = savePartyMonsterIDs;
    _saveSelectedMoveIDs = saveSelectedMoveIDs;
    _refreshDefinitions = refreshDefinitions;
    notifyListeners();
  }

  /// サーバーの図鑑に繋いでいる時は、定義を最新の master から読み直し、最後に届いた図鑑を反映し直す (対戦の前。相性表は
  /// 対戦時点の最新の版を両者に適用するため。documents/adr/0001-tech-stack.md。図鑑の読み込みに失敗した後のやり直しにも使う)。
  /// 繋いでいない時は何もしない。読み直しに失敗した時は例外を投げる。
  Future<void> refreshDefinitions() async => _refreshDefinitions?.call();

  /// サーバーの図鑑から離れ、空の端末の図鑑 (定義は [definitions]) に戻す (ログインを終えた時。別の uid の図鑑を残さないため)。
  void disconnectServer({required MasterData definitions}) {
    _savePartyMonsterIDs = null;
    _saveSelectedMoveIDs = null;
    _refreshDefinitions = null;
    _definitions = definitions;
    _monsters = [];
    _partyMonsterIDs = [];
    _serverError = null;
    notifyListeners();
  }

  /// サーバーから届いた図鑑 [monsters]・手持ち [partyMonsterIDs]・定義 [definitions] を反映する。null の項目は変えない。
  /// 読み込みの失敗の表示 ([serverError]) は、図鑑か定義を反映した時だけ消す (手持ちだけが届いても図鑑は直っていないため)。
  void applyServerSnapshot({
    required List<OwnedMonster>? monsters,
    required List<String>? partyMonsterIDs,
    required MasterData? definitions,
  }) {
    if (definitions != null) {
      _definitions = definitions;
    }
    if (monsters != null) {
      _monsters = List.of(monsters);
    }
    if (partyMonsterIDs != null) {
      _partyMonsterIDs = List.of(partyMonsterIDs);
    }
    if (monsters != null || definitions != null) {
      _serverError = null;
    }
    notifyListeners();
  }

  /// サーバーの図鑑の読み込みの失敗 [error] を残す (図鑑の画面に出す)。
  void reportServerError({required Object error}) {
    _serverError = error;
    notifyListeners();
  }

  /// [monsterID] のモンスターが図鑑に届いたら、そのモンスターを返す (生成の直後は Firestore の図鑑の反映を待つため)。
  /// [timeout] までに届かなければ [TimeoutException] を投げる。
  Future<OwnedMonster> waitForMonster({
    required String monsterID,
    required Duration timeout,
  }) {
    OwnedMonster? findMonster() => _monsters
        .where((monster) => monster.definition.id == monsterID)
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
              throw TimeoutException('モンスター $monsterID が図鑑に届きませんでした', timeout),
        )
        .whenComplete(() => removeListener(onChanged));
  }

  /// 図鑑にいる [monsterID] のモンスターを手持ちに入れる。
  /// 既に手持ちにいる・手持ちに空きが無い・図鑑にいない時は何もしない。保存に失敗した時は元に戻して例外を投げる。
  Future<void> addToParty({required String monsterID}) {
    if (isInParty(monsterID: monsterID) ||
        !hasPartyVacancy ||
        !contains(monsterID: monsterID)) {
      return Future.value();
    }
    return _changeParty(monsterIDs: [..._partyMonsterIDs, monsterID]);
  }

  /// 手持ちの [outgoingMonsterID] を、図鑑にいる [incomingMonsterID] と入れ替える (手持ちの中の位置は変えない)。
  /// [outgoingMonsterID] が手持ちにいない・[incomingMonsterID] が既に手持ちにいるか図鑑にいない時は何もしない。
  /// 保存に失敗した時は元に戻して例外を投げる。
  Future<void> replacePartyMember({
    required String outgoingMonsterID,
    required String incomingMonsterID,
  }) {
    if (!isInParty(monsterID: outgoingMonsterID) ||
        isInParty(monsterID: incomingMonsterID) ||
        !contains(monsterID: incomingMonsterID)) {
      return Future.value();
    }
    return _changeParty(
      monsterIDs: [
        for (final monsterID in _partyMonsterIDs)
          monsterID == outgoingMonsterID ? incomingMonsterID : monsterID,
      ],
    );
  }

  /// [monsterID] のモンスターを手持ちから外す。手持ちにいない時は何もしない。保存に失敗した時は元に戻して例外を投げる。
  Future<void> removeFromParty({required String monsterID}) {
    if (!isInParty(monsterID: monsterID)) {
      return Future.value();
    }
    return _changeParty(
      monsterIDs: [
        for (final partyMonsterID in _partyMonsterIDs)
          if (partyMonsterID != monsterID) partyMonsterID,
      ],
    );
  }

  /// 手持ちを [monsterIDs] にして、サーバーに繋いでいれば保存する。
  /// 画面にはすぐ反映し、保存に失敗したら変更の前に戻して例外を投げる (Firestore の手持ちと食い違わせないため)。
  /// 保存の途中に呼ばれた時は変えずに [StateError] を投げる (並んだ保存の片方が失敗した時に、もう片方の変更まで
  /// 巻き戻して食い違わせないため)。
  Future<void> _changeParty({required List<String> monsterIDs}) async {
    if (_isSavingParty) {
      throw StateError('手持ちを保存しています');
    }
    final previousPartyMonsterIDs = _partyMonsterIDs;
    _partyMonsterIDs = monsterIDs;
    _isSavingParty = true;
    notifyListeners();
    try {
      await _savePartyMonsterIDs?.call(monsterIDs: monsterIDs);
    } catch (_) {
      _partyMonsterIDs = previousPartyMonsterIDs;
      rethrow;
    } finally {
      _isSavingParty = false;
      notifyListeners();
    }
  }

  /// 図鑑のモンスターのレベルを [levelsByMonsterID] (monsterID ごとのレベル) に置き換える。図鑑にいない ID は無視する。
  /// サーバーの図鑑では、Functions が保存したレベルが Firestore から届くまでの間の表示に使う。
  void updateLevels({required Map<String, int> levelsByMonsterID}) {
    _monsters = [
      for (final monster in _monsters)
        levelsByMonsterID[monster.definition.id] == null
            ? monster
            : OwnedMonster(
                definition: monster.definition,
                level: levelsByMonsterID[monster.definition.id]!,
                actionCardMoveIDs: monster.actionCardMoveIDs,
                selectedMoveIDs: monster.selectedMoveIDs,
                artPath: monster.artPath,
                definitionIDs: monster.definitionIDs,
                decoration: monster.decoration,
                decorationVersion: monster.decorationVersion,
              ),
    ];
    notifyListeners();
  }

  /// 図鑑の [monsterID] のモンスターの Action Card で覚えさせた技を [actionCardMoveIDs] に置き換える。図鑑にいない時は何もしない。
  /// サーバーの図鑑では、teachActionCardMove・forgetActionCardMove が返した値を Firestore から届くまでの間に出すために使い、
  /// 端末だけの図鑑 (開発者メニューの見本の Action Card) では保存先の代わりにする。
  void updateActionCardMoveIDs({
    required String monsterID,
    required List<String> actionCardMoveIDs,
  }) {
    _monsters = [
      for (final monster in _monsters)
        monster.definition.id != monsterID
            ? monster
            : OwnedMonster(
                definition: monster.definition,
                level: monster.level,
                actionCardMoveIDs: List.unmodifiable(actionCardMoveIDs),
                selectedMoveIDs: monster.selectedMoveIDs,
                artPath: monster.artPath,
                definitionIDs: monster.definitionIDs,
                decoration: monster.decoration,
                decorationVersion: monster.decorationVersion,
              ),
    ];
    notifyListeners();
  }

  /// 図鑑の [monsterID] のモンスターの対戦の前に選んだ技を [moveIDs] (枠の順) にし、サーバーに繋いでいれば保存する
  /// (端末だけの図鑑ではメモリだけに持つ)。図鑑にいない時は何もしない。
  /// 画面にはすぐ反映し、保存に失敗した時は、待っている間に図鑑のそのモンスターが変わっていなければ選ぶ前に戻して例外を投げる
  /// (変わっていれば Firestore から届いた値の方が新しいため戻さない)。
  Future<void> selectMoves({
    required String monsterID,
    required List<String> moveIDs,
  }) async {
    final previousMonster = _monsters
        .where((monster) => monster.definition.id == monsterID)
        .firstOrNull;
    if (previousMonster == null) {
      return;
    }
    final selectedMonster = _replaceSelectedMoveIDs(
      monster: previousMonster,
      selectedMoveIDs: List.unmodifiable(moveIDs),
    );
    try {
      await _saveSelectedMoveIDs?.call(monsterID: monsterID, moveIDs: moveIDs);
    } catch (_) {
      if (_monsters.any((monster) => identical(monster, selectedMonster))) {
        _replaceSelectedMoveIDs(
          monster: selectedMonster,
          selectedMoveIDs: previousMonster.selectedMoveIDs,
        );
      }
      rethrow;
    }
  }

  /// 図鑑の [monster] を、選んだ技だけを [selectedMoveIDs] に置き換えたモンスターに差し替えて知らせ、差し替えたモンスターを返す。
  OwnedMonster _replaceSelectedMoveIDs({
    required OwnedMonster monster,
    required List<String>? selectedMoveIDs,
  }) {
    final replacedMonster = OwnedMonster(
      definition: monster.definition,
      level: monster.level,
      actionCardMoveIDs: monster.actionCardMoveIDs,
      selectedMoveIDs: selectedMoveIDs,
      artPath: monster.artPath,
      definitionIDs: monster.definitionIDs,
      decoration: monster.decoration,
      decorationVersion: monster.decorationVersion,
    );
    _monsters = [
      for (final dexMonster in _monsters)
        identical(dexMonster, monster) ? replacedMonster : dexMonster,
    ];
    notifyListeners();
    return replacedMonster;
  }

  /// 図鑑を [monsters] だけにし、先頭から [maximumPartySize] 体を手持ちにする (開発者メニューの見本の投入)。
  /// サーバーの図鑑に繋いでいる時は使わない (見本のモンスターはサーバーに無く、手持ちを保存できないため)。
  void replaceAll({required List<OwnedMonster> monsters}) {
    _monsters = List.of(monsters);
    _partyMonsterIDs = [
      for (final monster in monsters.take(maximumPartySize))
        monster.definition.id,
    ];
    notifyListeners();
  }

  /// 図鑑と手持ちを空にする。
  void clear() => replaceAll(monsters: const []);
}
