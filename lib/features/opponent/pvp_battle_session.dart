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

/// 自分の端末の向きの [state] を、公開されたターン [turn] の 2 人の行動で 1 ラウンド進めた状態 (自分の端末の向き) を返す。
/// [isHost] は自分が先に待っていた側かで、2 人の端末は同じ向き (先に待っていた側を利用者の陣営とする向き) で計算し、
/// 後から来た側は前後で陣営を入れ替える ([mirrorBattleState])。
/// 相手の端末から届いた行動が選べない行動 ([isSelectableAction]) の時は、ラウンドを進めずにその行動を出した側の負けで終える
/// (2 人とも選べない行動の時は、先に待っていた側の負け)。2 人の端末が同じ入力から同じ結果を出す。
BattleState resolvePvpRound({
  required BattleState state,
  required PvpTurn turn,
  required bool isHost,
  required MasterData definitions,
}) {
  final hostSideState = isHost ? state : mirrorBattleState(state: state);
  final nextHostSideState = switch ((
    isSelectableAction(
      party: hostSideState.player,
      action: turn.hostAction,
      master: definitions,
    ),
    isSelectableAction(
      party: hostSideState.opponent,
      action: turn.guestAction,
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
      playerAction: turn.hostAction,
      opponentAction: turn.guestAction,
      master: definitions,
    ),
  };
  return isHost
      ? nextHostSideState
      : mirrorBattleState(state: nextHostSideState);
}

/// 人との対戦 1 戦の同期。自分の行動を出し、2 人の行動の公開を待ってラウンドを進め、行動を選ぶ残り時間を数え、
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

  /// [remainingSeconds] の実体。
  final ValueNotifier<int> _remainingSeconds;

  /// 自分の計算で進め終えたラウンドの数 (= 次に行動を出すターンの 0 始まりの番号)。
  int _resolvedRoundCount = 0;

  /// 対戦の同期を終えたか (自分の計算で決着した対戦をサーバーも勝者を決めて終えた・[interruption] が完了した・[dispose] した)。
  bool _isSettled = false;

  /// 自分の計算で決着したか。決着した後は残り時間を数えず、サーバーが対戦を終えるのを待つ。
  bool _isDecided = false;

  /// [dispose] したか。
  bool _isDisposed = false;

  /// 行動を出して公開を待っているラウンド (進める前の状態と、進めた状態を返す先)。待っていない間は null。
  ({BattleState state, Completer<BattleState?> nextState})? _pendingRound;

  /// [interruption] の実体。
  final Completer<PvpBattleInterruption> _interruption = Completer();

  /// 対戦の状態の購読。[start] の前と同期を終えた後は null。
  StreamSubscription<PvpBattle?>? _battleSubscription;

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

  /// 今のターンの行動を選ぶ残り時間 (秒)。ターンが公開されるたびに [PvpBattle.turnSeconds] に戻り、0 で止まる。
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

  /// 同期を止める (購読とタイマーを止める)。公開を待っている [advance] は null で完了する。何度呼んでもよい (冪等)。
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
  /// 行動を出す呼び出しが失敗した時は、公開されるか対戦が終わるまで [_retryInterval] ごとにやり直す
  /// (通信が戻らなければ、行動を出せなかった側として時間切れで終わる)。
  Future<BattleState?> advance({
    required BattleState state,
    required BattleAction playerAction,
  }) {
    if (_isSettled || _isDecided) {
      return Future.value();
    }
    final nextState = Completer<BattleState?>();
    _pendingRound = (state: state, nextState: nextState);
    unawaited(_submitAction(round: _resolvedRoundCount, action: playerAction));
    return nextState.future;
  }

  /// [round] 番目のターンに [action] を出す。失敗した時は、そのターンが公開されるか同期を終えるまでやり直す。
  Future<void> _submitAction({
    required int round,
    required BattleAction action,
  }) async {
    while (!_isSettled && _resolvedRoundCount == round) {
      try {
        await client.submitAction(
          battleID: battleID,
          round: round,
          action: action,
        );
        return;
      } catch (error) {
        debugPrint('submitPvpAction: $error');
        await Future<void>.delayed(_retryInterval);
      }
    }
  }

  /// 対戦の状態 [battle] (消えた時は null) を受け取り、待っているラウンドを進め、対戦が終わっていれば [interruption] を完了する。
  void _onBattleChanged(PvpBattle? battle) {
    if (_isSettled) {
      return;
    }
    if (battle == null) {
      _interrupt(interruption: (winner: null));
      return;
    }
    _battle = battle;
    // 勝敗を付けずに終わった対戦は、同じ知らせに最後のターンが入っていても進めない
    // (進めて決着すると、この端末だけが勝敗を出して記録に進むため)
    if (battle.status == PvpBattleStatus.noContest) {
      _interrupt(interruption: (winner: null));
      return;
    }
    final pendingRound = _pendingRound;
    if (pendingRound != null && battle.turns.length > _resolvedRoundCount) {
      final nextState = resolvePvpRound(
        state: pendingRound.state,
        turn: battle.turns[_resolvedRoundCount],
        isHost: _isHost,
        definitions: definitions,
      );
      _pendingRound = null;
      _resolvedRoundCount += 1;
      if (nextState.winner != null) {
        // 購読は止めない。勝者を報告するのは最後のラウンドの演出の後で、それまでにサーバーが勝敗を付けずに終える
        // (相手がブロックした・対戦が消えた) ことがあるため、サーバーが対戦を終えるまで受け取り続ける
        _isDecided = true;
        _turnTimer?.cancel();
        _turnTimer = null;
      } else {
        _remainingSeconds.value = battle.turnSeconds;
        _secondsAfterDeadline = 0;
      }
      pendingRound.nextState.complete(nextState);
    }
    if (_isSettled || battle.status != PvpBattleStatus.finished) {
      return;
    }
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
    // 相手が勝者を報告したが、公開されたターンを進めた自分の計算では決着していない。
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

  /// 同期を終える (購読とタイマーを止め、公開を待っている [advance] を null で完了する)。
  void _settle() {
    _isSettled = true;
    unawaited(_battleSubscription?.cancel());
    _battleSubscription = null;
    _turnTimer?.cancel();
    _turnTimer = null;
    _pendingRound?.nextState.complete(null);
    _pendingRound = null;
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
