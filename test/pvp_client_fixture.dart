import 'dart:typed_data';

import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/opponent/pvp_battle_client.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/opponent/report_reason.dart';

import 'pvp_battle_fixture.dart';

/// テスト用の [PvpClient] が受け取った呼び出し。
class RecordedPvpCalls {
  /// fetchOpponents を呼んだ回数。
  int fetchOpponentsCount = 0;

  /// fetchDefinitions に渡された定義の ID (呼ばれた順)。
  final List<List<String>> fetchedDefinitionIDs = [];

  /// reportMonster に渡された引数 (呼ばれた順)。
  final List<({String monsterOwnerUid, String monsterID, ReportReason reason})>
  reports = [];

  /// blockUser に渡された引数 (呼ばれた順)。
  final List<({String blockedUid, String? battleID})> blocks = [];

  /// updateDisplayName に渡された名前 (呼ばれた順)。
  final List<String> updatedDisplayNames = [];

  /// updateIcon に渡された写真 (呼ばれた順)。
  final List<Uint8List> updatedIconPhotos = [];

  /// openContact を呼んだ回数。
  int openContactCount = 0;

  /// openContact が返す値 (お問い合わせの宛先を開けたか)。開けなかった時を確かめるテストが false にする。
  bool opensContact = true;
}

/// Firebase を呼ばずに [calls] へ呼び出しを残す [PvpClient] を返す。
/// fetchOpponents は [fetchOpponents] の結果を、fetchDefinitions は base に [extraDefinitions] を足した定義を返す
/// ([extraDefinitions] が null なら base のまま)。戦績とプロフィールは [battleRecord]・[profile] を返し、
/// 通報・ブロック・表示名とアイコンの変更は [reportMonster]・[blockUser]・[updateDisplayName]・[updateIcon] を呼ぶ。
/// 人との対戦の組み合わせと同期は [battleClient] に任せる (人との対戦をしないテストは [signedOutPvpBattleClient])。
/// お問い合わせは開かずに [RecordedPvpCalls.opensContact] を返す。
PvpClient fakePvpClient({
  required RecordedPvpCalls calls,
  required PvpBattleClient battleClient,
  required Future<List<PvpOpponent>?> Function() fetchOpponents,
  required MasterData? extraDefinitions,
  required ({int wins, int losses})? battleRecord,
  required PlayerProfile? profile,
  required Future<void> Function() reportMonster,
  required Future<void> Function() blockUser,
  required Future<String> Function({required String displayName})
  updateDisplayName,
  required Future<String> Function({required Uint8List photo}) updateIcon,
}) => PvpClient(
  fetchOpponents: () {
    calls.fetchOpponentsCount++;
    return fetchOpponents();
  },
  fetchDefinitions: ({required base, required definitionIDs}) async {
    calls.fetchedDefinitionIDs.add(definitionIDs);
    return extraDefinitions == null
        ? base
        : mergeMasterData(base: base, additional: extraDefinitions);
  },
  reportMonster:
      ({required monsterOwnerUid, required monsterID, required reason}) async {
        calls.reports.add((
          monsterOwnerUid: monsterOwnerUid,
          monsterID: monsterID,
          reason: reason,
        ));
        await reportMonster();
      },
  blockUser: ({required blockedUid, required battleID}) async {
    calls.blocks.add((blockedUid: blockedUid, battleID: battleID));
    await blockUser();
  },
  fetchBattleRecord: () async => battleRecord,
  fetchProfile: () async => profile,
  updateDisplayName: ({required displayName}) {
    calls.updatedDisplayNames.add(displayName);
    return updateDisplayName(displayName: displayName);
  },
  updateIcon: ({required photo}) {
    calls.updatedIconPhotos.add(photo);
    return updateIcon(photo: photo);
  },
  battleClient: battleClient,
  openContact: () async {
    calls.openContactCount++;
    return calls.opensContact;
  },
);

/// ログインが無い時の [PvpClient] (相手・戦績・プロフィールは null で、見本の対戦相手を代わりに出す)。
PvpClient signedOutPvpClient({required RecordedPvpCalls calls}) =>
    fakePvpClient(
      calls: calls,
      battleClient: signedOutPvpBattleClient(),
      fetchOpponents: () async => null,
      extraDefinitions: null,
      battleRecord: null,
      profile: null,
      reportMonster: () async {},
      blockUser: () async {},
      updateDisplayName: ({required displayName}) async => displayName,
      updateIcon: ({required photo}) async =>
          throw StateError('ログインしていないためアイコンを変えられません'),
    );
