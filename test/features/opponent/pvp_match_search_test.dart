import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/opponent/pvp_match_search.dart';

import '../../pvp_battle_fixture.dart';
import '../../sample_data_fixture.dart';

// 人との対戦の相手を探す 1 回の操作 (issue #386)。探している間の呼び直し・やめ方・失敗を確かめる。
void main() {
  final sampleData = loadSampleDataFixture();
  final player = pvpTrainerFixture(
    uid: 'player-uid',
    displayName: 'じぶん',
    monsters: [sampleData.monsterByID(monsterID: 'sample-mugmon')],
  );

  /// [player] が先に待つ、まだ組み合わせていない対戦のサーバー。
  FakePvpBattleServer unmatchedServer() => FakePvpBattleServer(
    host: player,
    guest: pvpTrainerFixture(
      uid: 'opponent-uid',
      displayName: 'あいて',
      monsters: [sampleData.monsterByID(monsterID: 'sample-noton')],
    ),
    randomSeed: 1,
    turnSeconds: 60,
  );

  /// [server] で [player] が版 `1.9` の相手を探す操作。
  PvpMatchSearch searchOf({required FakePvpBattleServer server}) =>
      PvpMatchSearch(
        client: server.clientOf(uid: player.uid),
        rulesVersion: '1.9',
      );

  test('対戦の計算の版は、バトルの計算の版と master の版の組で、master の版が違えば別の版になる', () {
    final definitions = sampleData.definitions;
    expect(
      pvpMatchRulesVersion(definitions: definitions),
      '1.${definitions.version}',
    );
    expect(
      pvpMatchRulesVersion(
        definitions: MasterData(
          version: definitions.version + 1,
          elementTypes: definitions.elementTypes,
          typeChart: definitions.typeChart,
          moves: definitions.moves,
          effects: definitions.effects,
          statGrades: definitions.statGrades,
          elementSelection: definitions.elementSelection,
        ),
      ),
      '1.${definitions.version + 1}',
    );
  });

  testWidgets('探している間は 3 秒ごとに同じ探す操作の ID で相手を探し、組み合わされたら対戦の ID を返して探すのをやめる', (
    tester,
  ) async {
    final server = unmatchedServer();
    final search = searchOf(server: server);
    String? matchedBattleID;
    var isCompleted = false;
    search.matchedBattleID.then((battleID) {
      matchedBattleID = battleID;
      isCompleted = true;
    }).ignore();

    search.start();
    await tester.pump();
    expect(server.joinCalls, [
      (uid: 'player-uid', rulesVersion: '1.9', searchID: 'search-1'),
    ]);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(server.joinCalls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(server.joinCalls, hasLength(2));
    await tester.pump(const Duration(seconds: 6));
    expect(server.joinCalls, hasLength(4));
    expect(server.joinCalls.map((call) => call.searchID).toSet(), {'search-1'});
    expect(isCompleted, isFalse);

    server.match();
    await tester.pump(const Duration(seconds: 3));
    expect(isCompleted, isTrue);
    expect(matchedBattleID, FakePvpBattleServer.battleID);
    expect(server.joinCalls, hasLength(5));

    await tester.pump(const Duration(seconds: 30));
    expect(server.joinCalls, hasLength(5));
    expect(server.leaveCalls, isEmpty);
  });

  testWidgets('組み合わされる前にやめると、探すのをやめると伝えて null を返し、その後は探さない', (tester) async {
    final server = unmatchedServer();
    final search = searchOf(server: server)..start();
    await tester.pump(const Duration(seconds: 4));
    expect(server.joinCalls, hasLength(2));

    expect(await search.stop(), isNull);

    expect(server.leaveCalls, [(uid: 'player-uid', searchID: 'search-1')]);
    expect(await search.matchedBattleID, isNull);
    await tester.pump(const Duration(seconds: 30));
    expect(server.joinCalls, hasLength(2));
  });

  testWidgets('やめる時に既に組み合わされていたら、その対戦の ID を返す', (tester) async {
    final server = unmatchedServer();
    final search = searchOf(server: server)..start();
    await tester.pump(const Duration(seconds: 1));
    // 次に相手を探す呼び出しの前に、後から来た相手と組み合わされた
    server.match();

    expect(await search.stop(), FakePvpBattleServer.battleID);
    expect(await search.matchedBattleID, FakePvpBattleServer.battleID);
  });

  testWidgets('何度やめても同じ結果を返し、探すのをやめると伝えるのは 1 回だけ', (tester) async {
    final server = unmatchedServer();
    final search = searchOf(server: server)..start();
    await tester.pump();

    expect(await search.stop(), isNull);
    expect(await search.stop(), isNull);

    expect(server.leaveCalls, hasLength(1));
  });

  testWidgets('組み合わされた後にやめても、探すのをやめると伝えない (相手が入っている対戦の札を消さない)', (tester) async {
    final server = unmatchedServer()..match();
    final search = searchOf(server: server)..start();
    await tester.pump();

    expect(await search.stop(), FakePvpBattleServer.battleID);

    expect(server.leaveCalls, isEmpty);
  });

  testWidgets('相手を探す呼び出しが失敗したら、その失敗を返して探すのをやめる', (tester) async {
    final server = unmatchedServer()..joinError = StateError('手持ちを入れてください');
    final search = searchOf(server: server);
    Object? searchError;
    search.matchedBattleID.then((_) {}, onError: (Object error) {
      searchError = error;
    }).ignore();

    search.start();
    await tester.pump();
    expect(searchError, isStateError);

    await tester.pump(const Duration(seconds: 30));
    expect(server.joinCalls, hasLength(1));
    await expectLater(search.stop(), throwsStateError);
    expect(server.leaveCalls, isEmpty);
  });
}
