import 'dart:async';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/pvp_battle.dart';
import 'package:snapmon/features/opponent/pvp_battle_client.dart';

/// ログインが無い時の [PvpBattleClient]。uid が無く、人との対戦の呼び出しはどれも失敗する
/// (ログインが無い時に人との対戦を探さないことを、呼ばれたら落ちることで確かめる)。
PvpBattleClient signedOutPvpBattleClient() => PvpBattleClient(
  signedInUID: () => null,
  createSearchID: () => throw StateError('ログインが無いのに相手を探そうとした'),
  joinMatch: ({required rulesVersion, required searchID}) =>
      throw StateError('ログインが無いのに joinMatch を呼んだ'),
  leaveMatch: ({required searchID}) =>
      throw StateError('ログインが無いのに leaveMatch を呼んだ'),
  watchBattle: ({required battleID}) =>
      throw StateError('ログインが無いのに watchBattle を呼んだ'),
  submitAction: ({required battleID, required round, required action}) =>
      throw StateError('ログインが無いのに submitAction を呼んだ'),
  claimTimeout: ({required battleID}) =>
      throw StateError('ログインが無いのに claimTimeout を呼んだ'),
  reportResult: ({required battleID, required winnerUID}) =>
      throw StateError('ログインが無いのに reportResult を呼んだ'),
);

/// 名前が [displayName]・手持ちが [monsters] の、uid が [uid] のテスト用の対戦の参加者を作る。
PvpTrainer pvpTrainerFixture({
  required String uid,
  required String displayName,
  required List<OwnedMonster> monsters,
}) => PvpTrainer(
  uid: uid,
  displayName: displayName,
  iconPath: null,
  monsters: monsters,
);

/// テスト用の、人との対戦の Functions (functions/src/pvp_battle.ts) と Firestore の `pvpBattles/{battleID}` の代わり。
/// [host] と [guest] の 1 戦だけを扱い、[match] を呼ぶまでは組み合わせていない。
/// 組み合わせた対戦は、Functions と同じく、組み合わせた時の探す操作の ID の joinMatch・leaveMatch にだけ返す
/// (新しい探す操作には前の対戦を返さない)。
/// 行動の公開・時間切れ・勝者の報告の決め方は Functions と同じにしてある (Functions の側は functions/test/emulator/pvp_battle.test.ts が確かめる)。
/// 期限は時計で数えず、テストが [isTurnDeadlinePassed] を true にした後の [PvpBattleClient.claimTimeout] だけが対戦を終える
/// (端末の時計が先に進んでも、サーバーの期限の前は終わらないことを確かめるため)。
class FakePvpBattleServer {
  /// [host] (先に待っていた側) と [guest] (後から来た側) の、乱数の種が [randomSeed]・1 ターンが [turnSeconds] 秒の対戦を扱うサーバーを作る。
  FakePvpBattleServer({
    required this.host,
    required this.guest,
    required this.randomSeed,
    required this.turnSeconds,
  });

  /// 対戦の ID。
  static const String battleID = 'pvp-battle';

  /// 先に待っていた側。
  final PvpTrainer host;

  /// 後から来た側。
  final PvpTrainer guest;

  /// バトルの乱数の種。
  final int randomSeed;

  /// 1 ターンの行動を選ぶ時間 (秒)。
  final int turnSeconds;

  /// joinMatch の呼び出し (呼ばれた順)。
  final List<({String uid, String rulesVersion, String searchID})> joinCalls =
      [];

  /// leaveMatch の呼び出し (呼ばれた順)。
  final List<({String uid, String searchID})> leaveCalls = [];

  /// submitAction の呼び出し (呼ばれた順。出し直しを含む)。
  final List<({String uid, int round, BattleAction action})> submitCalls = [];

  /// claimTimeout を呼んだ uid (呼ばれた順)。
  final List<String> timeoutClaimUIDs = [];

  /// reportResult の呼び出し (呼ばれた順)。
  final List<({String uid, String? winnerUID})> reportCalls = [];

  /// null 以外の時、joinMatch がこのエラーで失敗する。
  Object? joinError;

  /// null 以外の時、submitAction がこのエラーで失敗する (通信の失敗)。
  Object? submitError;

  /// 今のターンの行動の期限 (サーバーの時計) を過ぎたか。true の間の claimTimeout が対戦を終え、submitAction は失敗する。
  bool isTurnDeadlinePassed = false;

  /// 組み合わせた後の対戦。組み合わせる前と、[deleteBattle] の後は null。
  PvpBattle? _battle;

  /// 今のターンの、まだ公開していない行動 (uid ごと)。
  final Map<String, BattleAction> _pendingActions = {};

  /// 勝者を報告済みの uid。
  final Set<String> _reportedUIDs = {};

  /// 対戦の変化を、見ている端末に流す。
  final StreamController<PvpBattle?> _battleChanges =
      StreamController.broadcast();

  /// 作った探す操作の ID の数。
  int _searchIDCount = 0;

  /// 相手を探している利用者の待ちの札 (uid ごとの、探す操作の ID と組み合わされた対戦の ID)。
  final Map<String, ({String searchID, String? battleID})> _tickets = {};

  /// [match] の時に待ちの札が無かった利用者の uid。次に相手を探した時に、その探す操作を組み合わせる (後から来た側になる)。
  final Set<String> _uidsMatchedOnNextJoin = {};

  /// 今の対戦の状態。組み合わせる前は null。
  PvpBattle? get battle => _battle;

  /// 2 人を組み合わせる。相手を探している利用者には今の探す操作に、探していない利用者には次の探す操作に、対戦の ID を返すようになる。
  void match() {
    _update(
      turns: const [],
      status: PvpBattleStatus.active,
      winnerUID: null,
      finishReason: null,
    );
    for (final uid in [host.uid, guest.uid]) {
      if (_tickets[uid] case final ticket?) {
        _tickets[uid] = (searchID: ticket.searchID, battleID: battleID);
      } else {
        _uidsMatchedOnNextJoin.add(uid);
      }
    }
  }

  /// 進行中の対戦を、片方が相手をブロックした時と同じく勝敗を付けずに終える。
  void finishByBlock() => _finish(
    status: PvpBattleStatus.noContest,
    winnerUID: null,
    finishReason: PvpFinishReason.blocked,
  );

  /// 最後のターン [turn] の公開と、ブロックでの勝敗なしの終わりを、1 回の知らせで届ける
  /// (Firestore の購読は途中の状態を飛ばして最新の状態だけを届けることがあるため)。
  void finishByBlockAfterRevealing({required PvpTurn turn}) {
    _pendingActions.clear();
    _update(
      turns: [..._battle!.turns, turn],
      status: PvpBattleStatus.noContest,
      winnerUID: null,
      finishReason: PvpFinishReason.blocked,
    );
  }

  /// 対戦を消す (相手がアカウントを削除した時)。
  void deleteBattle() {
    _battle = null;
    _battleChanges.add(null);
  }

  /// uid が [uid] の利用者の端末が使う [PvpBattleClient] を返す。
  PvpBattleClient clientOf({required String uid}) => PvpBattleClient(
    signedInUID: () => uid,
    createSearchID: () => 'search-${++_searchIDCount}',
    joinMatch: ({required rulesVersion, required searchID}) async {
      joinCalls.add((uid: uid, rulesVersion: rulesVersion, searchID: searchID));
      if (joinError case final error?) {
        throw error;
      }
      if (_tickets[uid]?.searchID != searchID) {
        _tickets[uid] = (
          searchID: searchID,
          battleID: _uidsMatchedOnNextJoin.remove(uid) ? battleID : null,
        );
      }
      return _tickets[uid]!.battleID;
    },
    leaveMatch: ({required searchID}) async {
      leaveCalls.add((uid: uid, searchID: searchID));
      final ticket = _tickets[uid];
      if (ticket == null || ticket.searchID != searchID) {
        return null;
      }
      if (ticket.battleID == null) {
        _tickets.remove(uid);
      }
      return ticket.battleID;
    },
    watchBattle: ({required battleID}) => Stream.multi((controller) {
      controller.add(_battle);
      final battleChangesSubscription = _battleChanges.stream.listen(
        controller.add,
      );
      // 購読の解除の Future を返さない。返すと、解除を待つ `Stream.first` が widget テストの偽の時計の外 (ルートのゾーン) の
      // マイクロタスクを待つことになり、テストの中で完了しない
      controller.onCancel = () {
        unawaited(battleChangesSubscription.cancel());
      };
    }),
    submitAction:
        ({required battleID, required round, required action}) async =>
            submitAction(uid: uid, round: round, action: action),
    claimTimeout: ({required battleID}) async => claimTimeout(uid: uid),
    reportResult: ({required battleID, required winnerUID}) async =>
        reportResult(uid: uid, winnerUID: winnerUID),
  );

  /// [uid] の、[round] 番目のターンの行動 [action] を受け取る。2 人分そろったら公開する。
  void submitAction({
    required String uid,
    required int round,
    required BattleAction action,
  }) {
    submitCalls.add((uid: uid, round: round, action: action));
    if (submitError case final error?) {
      throw error;
    }
    final battle = _battle!;
    if (round < battle.turns.length) {
      return;
    }
    if (battle.status != PvpBattleStatus.active) {
      throw StateError('対戦は終わっています');
    }
    if (round > battle.turns.length) {
      throw StateError('まだ始まっていないターンです');
    }
    if (isTurnDeadlinePassed) {
      throw StateError('行動を選ぶ時間を過ぎました');
    }
    _pendingActions.putIfAbsent(uid, () => action);
    final hostAction = _pendingActions[host.uid];
    final guestAction = _pendingActions[guest.uid];
    if (hostAction != null && guestAction != null) {
      _pendingActions.clear();
      _update(
        turns: [
          ...battle.turns,
          (hostAction: hostAction, guestAction: guestAction),
        ],
        status: PvpBattleStatus.active,
        winnerUID: null,
        finishReason: null,
      );
    }
  }

  /// [uid] からの、今のターンを時間切れとして終える頼みを受け取る。期限 ([isTurnDeadlinePassed]) の前と、終わった対戦では何もしない。
  /// 行動を出したのが片方だけならその側の勝ち、どちらも出していなければ勝敗を付けずに終える。
  void claimTimeout({required String uid}) {
    timeoutClaimUIDs.add(uid);
    if (_battle?.status != PvpBattleStatus.active || !isTurnDeadlinePassed) {
      return;
    }
    if (_pendingActions.keys.singleOrNull case final submittedUID?) {
      _finish(
        status: PvpBattleStatus.finished,
        winnerUID: submittedUID,
        finishReason: PvpFinishReason.timeout,
      );
    } else {
      _finish(
        status: PvpBattleStatus.noContest,
        winnerUID: null,
        finishReason: PvpFinishReason.timeout,
      );
    }
  }

  /// [uid] の端末の計算が出した勝者 [winnerUID] (決着していなければ null) の報告を受け取る。
  /// 進行中の対戦は最初の報告の勝者で終え、報告で終わった対戦に食い違う報告が届いたら勝敗を付けずに終える。
  void reportResult({required String uid, required String? winnerUID}) {
    reportCalls.add((uid: uid, winnerUID: winnerUID));
    final battle = _battle!;
    if (_reportedUIDs.contains(uid)) {
      return;
    }
    if (battle.status == PvpBattleStatus.active) {
      if (winnerUID == null) {
        return;
      }
      _reportedUIDs.add(uid);
      _finish(
        status: PvpBattleStatus.finished,
        winnerUID: winnerUID,
        finishReason: PvpFinishReason.result,
      );
      return;
    }
    _reportedUIDs.add(uid);
    if (battle.status == PvpBattleStatus.finished &&
        battle.finishReason == PvpFinishReason.result &&
        winnerUID != battle.winnerUID) {
      _finish(
        status: PvpBattleStatus.noContest,
        winnerUID: null,
        finishReason: PvpFinishReason.mismatch,
      );
    }
  }

  /// 対戦を [status]・[winnerUID]・[finishReason] で終え、出したままの行動を消す。
  void _finish({
    required PvpBattleStatus status,
    required String? winnerUID,
    required PvpFinishReason finishReason,
  }) {
    _pendingActions.clear();
    _update(
      turns: _battle!.turns,
      status: status,
      winnerUID: winnerUID,
      finishReason: finishReason,
    );
  }

  /// 対戦を渡した値の状態にし、見ている端末に流す。
  void _update({
    required List<PvpTurn> turns,
    required PvpBattleStatus status,
    required String? winnerUID,
    required PvpFinishReason? finishReason,
  }) {
    _battle = PvpBattle(
      battleID: battleID,
      host: host,
      guest: guest,
      randomSeed: randomSeed,
      battleDate: DateTime(2026, 11, 19),
      turns: turns,
      turnSeconds: turnSeconds,
      status: status,
      winnerUID: winnerUID,
      finishReason: finishReason,
    );
    _battleChanges.add(_battle);
  }
}
