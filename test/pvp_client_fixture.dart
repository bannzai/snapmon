import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/opponent/report_reason.dart';

/// テスト用の [PvpClient] が受け取った呼び出し。
class RecordedPvpCalls {
  /// fetchOpponents を呼んだ回数。
  int fetchOpponentsCount = 0;

  /// fetchDefinitions に渡された定義の ID (呼ばれた順)。
  final List<List<String>> fetchedDefinitionIds = [];

  /// reportMonster に渡された引数 (呼ばれた順)。
  final List<({String monsterOwnerUid, String monsterId, ReportReason reason})>
  reports = [];

  /// blockUser に渡された uid (呼ばれた順)。
  final List<String> blockedUids = [];

  /// updateDisplayName に渡された名前 (呼ばれた順)。
  final List<String> updatedDisplayNames = [];
}

/// Firebase を呼ばずに [calls] へ呼び出しを残す [PvpClient] を返す。
/// fetchOpponents は [fetchOpponents] の結果を、fetchDefinitions は base に [extraDefinitions] を足した定義を返す
/// ([extraDefinitions] が null なら base のまま)。戦績と表示名は [battleRecord]・[displayName] を返し、
/// 通報・ブロック・表示名の変更は [reportMonster]・[blockUser]・[updateDisplayName] を呼ぶ。
PvpClient fakePvpClient({
  required RecordedPvpCalls calls,
  required Future<List<PvpOpponent>?> Function() fetchOpponents,
  required MasterData? extraDefinitions,
  required ({int wins, int losses})? battleRecord,
  required String? displayName,
  required Future<void> Function() reportMonster,
  required Future<void> Function() blockUser,
  required Future<String> Function({required String displayName})
  updateDisplayName,
}) => PvpClient(
  fetchOpponents: () {
    calls.fetchOpponentsCount++;
    return fetchOpponents();
  },
  fetchDefinitions: ({required base, required definitionIds}) async {
    calls.fetchedDefinitionIds.add(definitionIds);
    return extraDefinitions == null
        ? base
        : mergeMasterData(base: base, additional: extraDefinitions);
  },
  reportMonster:
      ({required monsterOwnerUid, required monsterId, required reason}) async {
        calls.reports.add((
          monsterOwnerUid: monsterOwnerUid,
          monsterId: monsterId,
          reason: reason,
        ));
        await reportMonster();
      },
  blockUser: ({required blockedUid}) async {
    calls.blockedUids.add(blockedUid);
    await blockUser();
  },
  fetchBattleRecord: () async => battleRecord,
  fetchDisplayName: () async => displayName,
  updateDisplayName: ({required displayName}) {
    calls.updatedDisplayNames.add(displayName);
    return updateDisplayName(displayName: displayName);
  },
);

/// ログインが無い時の [PvpClient] (相手・戦績・表示名は null で、見本の対戦相手を代わりに出す)。
PvpClient signedOutPvpClient({required RecordedPvpCalls calls}) =>
    fakePvpClient(
      calls: calls,
      fetchOpponents: () async => null,
      extraDefinitions: null,
      battleRecord: null,
      displayName: null,
      reportMonster: () async {},
      blockUser: () async {},
      updateDisplayName: ({required displayName}) async => displayName,
    );
