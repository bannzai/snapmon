import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/battle/battle_mirror.dart';
import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import '../battle/battle_recorder.dart';
import 'pvp_battle.dart';
import 'pvp_battle_client.dart';

/// 行動を出す呼び出しと、時間切れを頼む呼び出しをやり直す間隔。
/// 通信が戻った時と、サーバーの期限 (端末より猶予の分だけ遅い) が来た時に、数秒のうちに次の状態へ進める間隔にした。
const Duration _retryInterval = Duration(seconds: 3);

/// 計算の決着どおりに終わらなかった人との対戦の終わり方 (時間切れ・ブロック・2 人の勝者の食い違い・対戦の削除)。
typedef PvpBattleInterruption = ({
  /// 行動の期限を過ぎて勝った陣営 (自分の端末の向き)。勝敗を付けずに終わった時は null。
  BattleSideID? winner,
});

/// 自分の端末の向きの [state] を、同じターンに 2 人が出した行動 (先に待っていた側の [hostAction] と後から来た側の [guestAction]) で
/// 1 ラウンド進めた状態 (自分の端末の向き) を返す。
/// [isHost] は自分が先に待っていた側かで、2 人の端末は同じ向き (先に待っていた側を利用者の陣営とする向き) で計算し、
/// 後から来た側は前後で陣営を入れ替える ([mirrorBattleState])。
/// 相手の端末から届いた行動が選べない行動 ([isSelectableAction]) の時は、ラウンドを進めずにその行動を出した側の負けで終える
/// (2 人とも選べない行動の時は、先に待っていた側の負け)。2 人の端末が同じ入力から同じ結果を出す。
BattleState resolvePvpRound({
  required BattleState state,
  required BattleAction hostAction,
  required BattleAction guestAction,
  required bool isHost,
  required MasterData definitions,
}) {
  final hostSideState = isHost ? state : mirrorBattleState(state: state);
  final nextHostSideState = switch ((
    isSelectableAction(
      party: hostSideState.player,
      action: hostAction,
      master: definitions,
    ),
    isSelectableAction(
      party: hostSideState.opponent,
      action: guestAction,
      master: definitions,
    ),
  )) {
    (false, _) => finishBattleByForfeit(
      state: hostSideState,
      winner: BattleSideID.opponent,
    ),
    (true, false) => finishBattleByForfeit(
      state: hostSideState,
      winner: BattleSideID.player,
    ),
    (true, true) => advanceRound(
      state: hostSideState,
      playerAction: hostAction,
      opponentAction: guestAction,
      master: definitions,
    ),
  };
  return isHost
      ? nextHostSideState
      : mirrorBattleState(state: nextHostSideState);
}

/// 人との対戦 1 戦の同期。自分の行動を出し、相手の同じターンの行動を待ってラウンドを進め、行動を選ぶ残り時間を数え、
/// 計算の決着の前に対戦が終わったこと (時間切れ・ブロック等) を知らせる。
/// バトルの画面が [start] で始め、画面を閉じる時に [dispose] する。途中でアプリを閉じた対戦は再開せず、時間切れで終わる。
class PvpBattleSession {
  /// [client] で、自分の uid が [playerUID] の対戦 [battle] (組み合わせた直後の状態) の同期を作る。
  /// [definitions] は 2 人の手持ちの属性・技を引ける定義。
  PvpBattleSession({
    required this.client,
    required PvpBattle battle,
    required this.playerUID,
    required this.definitions,
  }) : _battle = battle,
       _remainingSeconds = ValueNotifier(battle.turnSeconds);

  /// 対戦の同期を呼ぶ関数の組。
  final PvpBattleClient client;

  /// 自分の uid。
  final String playerUID;

  /// 2 人の手持ちの属性・技を引ける定義。
  final MasterData definitions;

  /// 最後に受け取った対戦の状態。
  PvpBattle _battle;

  /// 待っているターン ([_pendingTurn]) に相手が出した行動。まだ届いていない間と、待っていない間は null。
  /// 対戦の状態とは別の購読で届く。
  BattleAction? _opponentAction;

  /// [remainingSeconds] の実体。
  final ValueNotifier<int> _remainingSeconds;

  /// 次に自分が行動を出すターンの番号。[PvpBattle.turnNumber] と同じ数え方 (0 始まり) で、自分の計算で 2 人の行動を進め終えるたびに 1 増える。
  /// バトルの計算の状態からは求めない (選べない行動で終える [finishBattleByForfeit] は [BattleState.turnNumber] を進めないため)。
  int _turnNumber = 0;

  /// 対戦の同期を終えたか (自分の計算で決着した対戦をサーバーも勝者を決めて終えた・[interruption] が完了した・[dispose] した)。
  bool _isSettled = false;

  /// 自分の計算で決着したか。決着した後は残り時間を数えず、サーバーが対戦を終えるのを待つ。
  bool _isDecided = false;

  /// [dispose] したか。
  bool _isDisposed = false;

  /// 行動を出して相手の行動を待っているターン (進める前の状態・自分が出した行動・進めた状態を返す先)。待っていない間は null。
  ({
    BattleState state,
    BattleAction playerAction,
    Completer<BattleState?> nextState,
  })?
  _pendingTurn;

  /// [interruption] の実体。
  final Completer<PvpBattleInterruption> _interruption = Completer();

  /// 対戦の状態の購読。[start] の前と同期を終えた後は null。
  StreamSubscription<PvpBattle?>? _battleSubscription;

  /// 待っているターンに相手が出す行動の購読。自分の行動を出し終えてから始める。待っていない間は null。
  StreamSubscription<BattleAction?>? _opponentActionSubscription;

  /// 残り時間を 1 秒ずつ数えるタイマー。[start] の前と同期を終えた後は null。
  Timer? _turnTimer;

  /// 残り時間が 0 になってから数えた秒数。[_retryInterval] ごとに時間切れを頼み直すのに使う。
  int _secondsAfterDeadline = 0;

  /// 自分が先に待っていた側か。
  bool get _isHost => _battle.host.uid == playerUID;

  /// 対戦の ID。
  String get battleID => _battle.battleID;

  /// 対戦日。
  DateTime get battleDate => _battle.battleDate;

  /// 自分 (組み合わせた時点の手持ちの写し)。
  PvpTrainer get player => _isHost ? _battle.host : _battle.guest;

  /// 相手。
  PvpTrainer get opponent => _isHost ? _battle.guest : _battle.host;

  /// 今のターンの行動を選ぶ残り時間 (秒)。ターンが進むたびに [PvpBattle.turnSeconds] に戻り、0 で止まる。
  /// 端末が対戦の状態を受け取った時から数えるため、サーバーの期限より早く 0 になる (0 の後に出した行動も、サーバーの期限の前なら通る)。
  ValueListenable<int> get remainingSeconds => _remainingSeconds;

  /// 計算の決着の前に対戦が終わった時に、その終わり方で完了する。
  /// 計算で決着した後でも、サーバーが勝者を決める前に勝敗を付けずに終えた時 (相手がブロックした・対戦が消えた) は、勝敗なしで完了する。
  /// 計算で決着してサーバーも勝者を決めた対戦と、[dispose] した対戦では完了しない。
  Future<PvpBattleInterruption> get interruption => _interruption.future;

  /// 対戦の状態の購読と、残り時間のカウントを始める。
  void start() {
    // 読めなかった時は終わり方が分からないため対戦を止めず、時間切れを頼む呼び出しの結果に任せる
    _battleSubscription = client
        .watchBattle(battleID: battleID)
        .listen(
          _onBattleChanged,
          onError: (Object error) => debugPrint('watchBattle: $error'),
        );
    _turnTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onSecondElapsed(),
    );
  }

  /// 同期を止める (購読とタイマーを止める)。相手の行動を待っている [advance] は null で完了する。何度呼んでもよい (冪等)。
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _settle();
    _remainingSeconds.dispose();
  }

  /// 自分の端末の向きの [state] から、自分の行動 [playerAction] を出して相手の行動を待ち、1 ラウンド進めた状態を返す。
  /// 待つ間に対戦が終わった時 ([interruption]) と [dispose] した時は null を返す。
  /// 行動を出す呼び出しと、相手の行動の読み取りが失敗した時は、ターンが進むか対戦が終わるまで [_retryInterval] ごとにやり直す
  /// (通信が戻らなければ、行動を出せなかった側として時間切れで終わる)。
  Future<BattleState?> advance({
    required BattleState state,
    required BattleAction playerAction,
  }) {
    if (_isSettled || _isDecided) {
      return Future.value();
    }
    final nextState = Completer<BattleState?>();
    _pendingTurn = (
      state: state,
      playerAction: playerAction,
      nextState: nextState,
    );
    unawaited(_submitAction(turnNumber: _turnNumber, action: playerAction));
    return nextState.future;
  }

  /// [turnNumber] 番目のターンに [action] を出し、出し終えたら相手の同じターンの行動の購読を始める ([_watchOpponentAction])。
  /// 失敗した時は、ターンが進むか同期を終えるまでやり直す。
  Future<void> _submitAction({
    required int turnNumber,
    required BattleAction action,
  }) async {
    while (!_isSettled && _turnNumber == turnNumber) {
      try {
        await client.submitAction(
          battleID: battleID,
          turnNumber: turnNumber,
          action: action,
        );
        break;
      } catch (error) {
        debugPrint('submitPvpAction: $error');
        await Future<void>.delayed(_retryInterval);
      }
    }
    _watchOpponentAction(turnNumber: turnNumber);
  }

  /// [turnNumber] 番目のターンに相手が出す行動の購読を始める。そのターンを待っていない時 (進んだ・同期を終えた) は何もしない。
  /// 自分の行動を出し終えてから呼ぶ (出す前の読み取りは Rules が通さない)。
  /// 読めなかった時は、[_retryInterval] の後に購読し直す (ターンが進むか同期を終えるまで)。
  void _watchOpponentAction({required int turnNumber}) {
    if (_isSettled || _pendingTurn == null || _turnNumber != turnNumber) {
      return;
    }
    unawaited(_opponentActionSubscription?.cancel());
    _opponentActionSubscription = client
        .watchTurnAction(
          battleID: battleID,
          uid: opponent.uid,
          turnNumber: turnNumber,
        )
        .listen(
          (opponentAction) {
            if (_isSettled ||
                opponentAction == null ||
                _turnNumber != turnNumber) {
              return;
            }
            _opponentAction = opponentAction;
            _reconcile();
          },
          onError: (Object error) {
            debugPrint('watchTurnAction: $error');
            unawaited(
              Future<void>.delayed(
                _retryInterval,
              ).then((_) => _watchOpponentAction(turnNumber: turnNumber)),
            );
          },
        );
  }

  /// 対戦の状態 [battle] (消えた時は null) を受け取り、[_reconcile] する。
  void _onBattleChanged(PvpBattle? battle) {
    if (_isSettled) {
      return;
    }
    if (battle == null) {
      _interrupt(interruption: (winner: null));
      return;
    }
    _battle = battle;
    _reconcile();
  }

  /// 最後に受け取った対戦の状態と相手の行動から、待っているターンを進め、対戦が終わっていれば [interruption] を完了する。
  /// 対戦の状態と相手の行動は別の購読で届き、届く順は決まっていないため、どちらが届いた時も同じ判定をする。
  void _reconcile() {
    final battle = _battle;
    // 勝敗を付けずに終わった対戦は、最後のターンの行動が届いていても進めない
    // (進めて決着すると、この端末だけが勝敗を出して記録に進むため)
    if (battle.isNoContest) {
      _interrupt(interruption: (winner: null));
      return;
    }
    final pendingTurn = _pendingTurn;
    final opponentAction = _opponentAction;
    if (pendingTurn != null && opponentAction != null) {
      final nextState = resolvePvpRound(
        state: pendingTurn.state,
        hostAction: _isHost ? pendingTurn.playerAction : opponentAction,
        guestAction: _isHost ? opponentAction : pendingTurn.playerAction,
        isHost: _isHost,
        definitions: definitions,
      );
      _pendingTurn = null;
      _opponentAction = null;
      unawaited(_opponentActionSubscription?.cancel());
      _opponentActionSubscription = null;
      _turnNumber += 1;
      if (nextState.winner != null) {
        // 購読は止めない。勝者を報告するのは最後のターンの演出の後で、それまでにサーバーが勝敗を付けずに終える
        // (相手がブロックした・対戦が消えた) ことがあるため、サーバーが対戦を終えるまで受け取り続ける
        _isDecided = true;
        _turnTimer?.cancel();
        _turnTimer = null;
      } else {
        _remainingSeconds.value = battle.turnSeconds;
        _secondsAfterDeadline = 0;
      }
      pendingTurn.nextState.complete(nextState);
    }
    if (_isSettled || !battle.isFinished) {
      return;
    }
    // 2 人とも出したターンの相手の行動がまだ届いていない間は、終わり方を判定しない (行動が届いて進めた後に、もう一度ここへ来る)。
    // 先に判定すると、最後のターンで決着した対戦の相手の報告を「自分の計算では決着していない」と扱い、勝敗なしにしてしまう
    if (_isDecided) {
      // 自分の計算で決着した対戦を、サーバーも勝者を決めて終えた。途中で終わった扱いにしない
      _settle();
      return;
    }
    if (battle.finishReason == PvpFinishReason.timeout) {
      _interrupt(
        interruption: (
          winner: battle.winnerUID == playerUID
              ? BattleSideID.player
              : BattleSideID.opponent,
        ),
      );
      return;
    }
    // 相手が勝者を報告したが、2 人が出した行動をすべて進めた自分の計算では決着していない。
    // 決着していないと報告して勝敗を付けずに終える (報告を出せなくても、この端末では勝敗なしとして閉じる)
    unawaited(
      client
          .reportResult(battleID: battleID, winnerUID: null)
          .catchError((Object error) => debugPrint('reportPvpResult: $error')),
    );
    _interrupt(interruption: (winner: null));
  }

  /// 残り時間を 1 秒減らす。0 になった時と、その後 [_retryInterval] ごとに、今のターンを時間切れとして終えるよう頼む
  /// (相手を待っている時も、自分が選ばなかった時も頼む。期限はサーバーの時計で判定され、前に頼んでも何も変わらない)。
  void _onSecondElapsed() {
    if (_remainingSeconds.value > 0) {
      _remainingSeconds.value -= 1;
      if (_remainingSeconds.value > 0) {
        return;
      }
    } else {
      _secondsAfterDeadline += 1;
      if (_secondsAfterDeadline % _retryInterval.inSeconds != 0) {
        return;
      }
    }
    unawaited(
      client
          .claimTimeout(battleID: battleID)
          .catchError((Object error) => debugPrint('claimPvpTimeout: $error')),
    );
  }

  /// 計算の決着の前に対戦が終わったとして同期を終え、[interruption] を完了する。
  void _interrupt({required PvpBattleInterruption interruption}) {
    _settle();
    _interruption.complete(interruption);
  }

  /// 同期を終える (購読とタイマーを止め、相手の行動を待っている [advance] を null で完了する)。
  void _settle() {
    _isSettled = true;
    unawaited(_battleSubscription?.cancel());
    _battleSubscription = null;
    unawaited(_opponentActionSubscription?.cancel());
    _opponentActionSubscription = null;
    _opponentAction = null;
    _turnTimer?.cancel();
    _turnTimer = null;
    _pendingTurn?.nextState.complete(null);
    _pendingTurn = null;
  }
}

/// 人との対戦 [session] の結果を記録する [BattleRecorder] を返す。計測は [base] のまま送る。
/// 開始の記録は組み合わせた時に Functions が作っているため、startBattleRecord は呼び出しをせずに対戦の ID を返す。
/// completeBattleRecord は、自分の計算の勝者を Functions に報告してから (2 人の報告で勝敗が決まる)、
/// [base] でレベルを記録する (CPU との対戦と同じ recordBattle。1 日の上限とレベル +1 を同じに扱う)。
BattleRecorder pvpBattleRecorder({
  required BattleRecorder base,
  required PvpBattleSession session,
}) => BattleRecorder(
  startBattleRecord: ({required partyMonsterIDs}) async => session.battleID,
  completeBattleRecord:
      ({
        required battleID,
        required participantMonsterIDs,
        required winner,
        required turnCount,
      }) async {
        await session.client.reportResult(
          battleID: battleID,
          winnerUID: switch (winner) {
            BattleSideID.player => session.player.uid,
            BattleSideID.opponent => session.opponent.uid,
          },
        );
        return base.completeBattleRecord(
          battleID: battleID,
          participantMonsterIDs: participantMonsterIDs,
          winner: winner,
          turnCount: turnCount,
        );
      },
  logEvent: base.logEvent,
);
