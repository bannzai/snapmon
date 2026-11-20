import '../../domain/battle/battle_state.dart';
import 'pvp_battle.dart';

/// 人との対戦 (同じ時に相手を探している利用者と組み合わされ、互いに自分の端末で行動を選ぶ対戦) の、
/// 組み合わせと対戦の同期を呼ぶ関数の組。Functions (functions/src/pvp_battle.ts) と Firestore の `pvpBattles/{battleID}`・`pvpBattles/{battleID}/turns` に対応する。
/// 画面を Firebase と切り離してテストするため、実体 (lib/firebase/pvp_battle.dart) は main.dart から渡す。
class PvpBattleClient {
  /// 関数の組を作る。
  const PvpBattleClient({
    required this.signedInUID,
    required this.createSearchID,
    required this.joinMatch,
    required this.leaveMatch,
    required this.watchBattle,
    required this.watchTurnAction,
    required this.submitAction,
    required this.claimTimeout,
    required this.reportResult,
  });

  /// ログインしている利用者の uid を返す。ログインが無い時 (DEBUG ビルドでログインを飛ばした時) は null で、人との対戦は探せない。
  final String? Function() signedInUID;

  /// 1 回の探す操作の ID を作る。Functions が、前の探す操作で組み合わされた対戦を新しい探す操作の結果として返さないために使う。
  final String Function() createSearchID;

  /// 対戦の計算の版 [rulesVersion] と探す操作の ID [searchID] で相手を探し、組み合わされた対戦の ID を返す。まだなら null。
  /// 探している間は同じ [searchID] で呼び直す (呼ばなくなった利用者は、相手に選ばれなくなる)。
  final Future<String?> Function({
    required String rulesVersion,
    required String searchID,
  })
  joinMatch;

  /// [searchID] の探す操作をやめる。やめる前に組み合わされていたらその対戦の ID を返し (相手は既に対戦に入っている)、そうでなければ null。
  final Future<String?> Function({required String searchID}) leaveMatch;

  /// 対戦 [battleID] の今の状態と、その後の変化を流す。対戦が消えた時 (相手がアカウントを削除した時) は null を流す。
  final Stream<PvpBattle?> Function({required String battleID}) watchBattle;

  /// 対戦 [battleID] の [turnNumber] 番目 (0 始まり) のターンに利用者 [uid] が出した行動と、その後の変化を流す。まだ出していない間は null を流す。
  /// 自分がそのターンの行動を出した後にだけ読める (相手の行動を見てから選べないようにするため。firebase/firestore.rules)。
  /// 出す前に購読すると、エラーを流す。
  final Stream<BattleAction?> Function({
    required String battleID,
    required String uid,
    required int turnNumber,
  })
  watchTurnAction;

  /// 対戦 [battleID] の [turnNumber] 番目 (0 始まり) のターンに、自分の行動 [action] を出す。同じターンの出し直しは何も変えない。
  final Future<void> Function({
    required String battleID,
    required int turnNumber,
    required BattleAction action,
  })
  submitAction;

  /// 対戦 [battleID] の今のターンを時間切れとして終えるよう頼む。期限 (サーバーの時計) の前に呼んでも何も変わらない。
  final Future<void> Function({required String battleID}) claimTimeout;

  /// 対戦 [battleID] の、自分の端末の計算が出した勝者の uid [winnerUID] を報告する。
  /// 2 人が出した行動では決着していない (相手が勝者を報告したが、自分の計算では決着していない) 時は null を渡す。
  final Future<void> Function({
    required String battleID,
    required String? winnerUID,
  })
  reportResult;
}
