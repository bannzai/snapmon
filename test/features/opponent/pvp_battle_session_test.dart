import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_mirror.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/opponent/pvp_battle.dart';
import 'package:snapmon/features/opponent/pvp_battle_session.dart';

import '../../battle_recorder_fixture.dart';
import '../../battle_state_description.dart';
import '../../pvp_battle_fixture.dart';
import '../../sample_data_fixture.dart';

// 人との対戦の同期 (issue #386)。2 人の端末が同じ行動の列から同じ結果を出すこと、片方が操作をやめた対戦がもう片方で終わること、
// 勝敗を付けない終わり方を確かめる。サーバーの代わりは test/pvp_battle_fixture.dart の FakePvpBattleServer。
void main() {
  final sampleData = loadSampleDataFixture();
  final definitions = sampleData.definitions;
  final host = pvpTrainerFixture(
    uid: 'host-uid',
    displayName: 'ホスト',
    monsters: [
      sampleData.monsterByID(monsterID: 'sample-mugmon'),
      sampleData.monsterByID(monsterID: 'sample-keybon'),
    ],
  );
  final guest = pvpTrainerFixture(
    uid: 'guest-uid',
    displayName: 'ゲスト',
    monsters: [
      sampleData.monsterByID(monsterID: 'sample-noton'),
      sampleData.monsterByID(monsterID: 'sample-slippan'),
    ],
  );

  /// 1 ターンが 60 秒の、組み合わせ済みの [host] と [guest] の対戦のサーバー。
  FakePvpBattleServer matchedServer() => FakePvpBattleServer(
    host: host,
    guest: guest,
    randomSeed: 20261119,
    turnSeconds: 60,
  )..match();

  /// [server] の対戦の、[player] の端末の同期。
  PvpBattleSession sessionOf({
    required FakePvpBattleServer server,
    required PvpTrainer player,
  }) => PvpBattleSession(
    client: server.clientOf(uid: player.uid),
    battle: server.battle!,
    playerUid: player.uid,
    definitions: definitions,
  );

  /// [player] の端末の向きの、[opponent] との対戦の最初の状態 (バトルの画面が作るのと同じく補正なし)。
  BattleState startStateOf({
    required PvpTrainer player,
    required PvpTrainer opponent,
  }) => startBattle(
    playerMembers: [
      for (final monster in player.monsters)
        prepareBattleMonster(
          definition: monster.definition,
          level: monster.level,
          experience: 0,
          actionCardMoveIDs: monster.actionCardMoveIDs,
          selectedMoveIDs: monster.selectedMoveIDs,
          master: definitions,
          maximumHitPointsPercent: 100,
        ),
    ],
    opponentMembers: [
      for (final monster in opponent.monsters)
        prepareBattleMonster(
          definition: monster.definition,
          level: monster.level,
          experience: 0,
          actionCardMoveIDs: monster.actionCardMoveIDs,
          selectedMoveIDs: monster.selectedMoveIDs,
          master: definitions,
          maximumHitPointsPercent: 100,
        ),
    ],
    randomSeed: 20261119,
    battleDate: DateTime(2026, 11, 19),
    opponentDamagePercent: 100,
  );

  /// [state] の利用者の陣営が CPU の規則で選ぶ行動 (テストで 2 人の操作の代わりに使う)。
  BattleAction chosenAction({required BattleState state}) => chooseCpuAction(
    state: state,
    side: BattleSideID.player,
    master: definitions,
  );

  group('resolvePvpRound', () {
    test('2 人の端末は、同じ行動の列から、陣営だけを入れ替えた同じ状態を決着まで出し続ける', () {
      var hostState = startStateOf(player: host, opponent: guest);
      var guestState = startStateOf(player: guest, opponent: host);
      // 300 ラウンド: 手持ち 2 体ずつの対戦が決着する数より十分多く、決着しない不具合でテストが止まらない上限
      for (var round = 0; round < 300 && hostState.winner == null; round++) {
        final PvpTurn turn = (
          hostAction: chosenAction(state: hostState),
          guestAction: chosenAction(state: guestState),
        );
        hostState = resolvePvpRound(
          state: hostState,
          turn: turn,
          isHost: true,
          definitions: definitions,
        );
        guestState = resolvePvpRound(
          state: guestState,
          turn: turn,
          isHost: false,
          definitions: definitions,
        );
        expect(
          describeBattleState(state: guestState),
          describeBattleState(state: mirrorBattleState(state: hostState)),
          reason: 'ラウンド $round',
        );
      }
      expect(hostState.winner, isNotNull);
      expect(guestState.winner, otherSide(side: hostState.winner!));
    });

    test('先に待っていた側の端末の結果は、その側を利用者の陣営にして進めた計算と同じ', () {
      final hostState = startStateOf(player: host, opponent: guest);
      final PvpTurn turn = (
        hostAction: chosenAction(state: hostState),
        guestAction: chosenAction(
          state: startStateOf(player: guest, opponent: host),
        ),
      );

      expect(
        describeBattleState(
          state: resolvePvpRound(
            state: hostState,
            turn: turn,
            isHost: true,
            definitions: definitions,
          ),
        ),
        describeBattleState(
          state: advanceRound(
            state: hostState,
            playerAction: turn.hostAction,
            opponentAction: turn.guestAction,
            master: definitions,
          ),
        ),
      );
    });

    /// 最初のターンに [hostAction] と [guestAction] が公開された時の、2 人の端末の勝った陣営と、ラウンドを進めたか。
    ({BattleSideID? hostWinner, BattleSideID? guestWinner, bool advanced})
    resolveFirstTurn({
      required BattleAction hostAction,
      required BattleAction guestAction,
    }) {
      final hostStart = startStateOf(player: host, opponent: guest);
      final hostState = resolvePvpRound(
        state: hostStart,
        turn: (hostAction: hostAction, guestAction: guestAction),
        isHost: true,
        definitions: definitions,
      );
      return (
        hostWinner: hostState.winner,
        guestWinner: resolvePvpRound(
          state: startStateOf(player: guest, opponent: host),
          turn: (hostAction: hostAction, guestAction: guestAction),
          isHost: false,
          definitions: definitions,
        ).winner,
        advanced: hostState.randomState != hostStart.randomState,
      );
    }

    // sample-mugmon (host の先頭) は fire_1 を、sample-noton (guest の先頭) は paper_1 を Lv.1 で覚える。
    // water_1 はどちらも覚えない (assets/samples/sample_monsters.json)
    test('2 人とも選べる行動なら、ラウンドを進めて決着を付けない', () {
      expect(
        resolveFirstTurn(
          hostAction: const UseMoveAction(moveID: 'fire_1'),
          guestAction: const UseMoveAction(moveID: 'paper_1'),
        ),
        (hostWinner: null, guestWinner: null, advanced: true),
      );
    });

    test('後から来た側が選べない行動を出したら、ラウンドを進めずに、2 人の端末とも先に待っていた側の勝ちにする', () {
      expect(
        resolveFirstTurn(
          hostAction: const UseMoveAction(moveID: 'fire_1'),
          guestAction: const UseMoveAction(moveID: 'water_1'),
        ),
        (
          hostWinner: BattleSideID.player,
          guestWinner: BattleSideID.opponent,
          advanced: false,
        ),
      );
    });

    test('先に待っていた側が選べない行動を出したら、2 人の端末とも後から来た側の勝ちにする', () {
      expect(
        resolveFirstTurn(
          hostAction: const SwitchMonsterAction(memberIndex: 0),
          guestAction: const UseMoveAction(moveID: 'paper_1'),
        ),
        (
          hostWinner: BattleSideID.opponent,
          guestWinner: BattleSideID.player,
          advanced: false,
        ),
      );
    });

    test('2 人とも選べない行動を出したら、先に待っていた側の負けにする', () {
      expect(
        resolveFirstTurn(
          hostAction: const UseMoveAction(moveID: 'water_1'),
          guestAction: const UseMoveAction(moveID: 'water_1'),
        ),
        (
          hostWinner: BattleSideID.opponent,
          guestWinner: BattleSideID.player,
          advanced: false,
        ),
      );
    });
  });

  group('PvpBattleSession', () {
    testWidgets('2 人が行動を出すたびに 2 人の端末のラウンドが進み、決着まで陣営だけを入れ替えた同じ状態になる', (
      tester,
    ) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      final guestSession = sessionOf(server: server, player: guest)..start();
      addTearDown(hostSession.dispose);
      addTearDown(guestSession.dispose);
      var hostState = startStateOf(player: host, opponent: guest);
      var guestState = startStateOf(player: guest, opponent: host);

      for (var round = 0; round < 300 && hostState.winner == null; round++) {
        final hostNext = hostSession.advance(
          state: hostState,
          playerAction: chosenAction(state: hostState),
        );
        final guestNext = guestSession.advance(
          state: guestState,
          playerAction: chosenAction(state: guestState),
        );
        await tester.pump();
        hostState = (await hostNext)!;
        guestState = (await guestNext)!;
        expect(server.battle!.turns, hasLength(round + 1));
        expect(
          describeBattleState(state: guestState),
          describeBattleState(state: mirrorBattleState(state: hostState)),
          reason: 'ラウンド $round',
        );
      }

      expect(hostState.winner, isNotNull);
      expect(guestState.winner, otherSide(side: hostState.winner!));
    });

    testWidgets('相手が行動を出すまでラウンドは進まず、出した時に進む', (tester) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      final hostState = startStateOf(player: host, opponent: guest);
      BattleState? resolvedState;
      var isResolved = false;

      hostSession
          .advance(
            state: hostState,
            playerAction: const UseMoveAction(moveID: 'fire_1'),
          )
          .then((state) {
            resolvedState = state;
            isResolved = true;
          })
          .ignore();
      await tester.pump(const Duration(seconds: 10));
      expect(isResolved, isFalse);
      expect(server.submitCalls.single.uid, host.uid);

      server.submitAction(
        uid: guest.uid,
        round: 0,
        action: const UseMoveAction(moveID: 'paper_1'),
      );
      await tester.pump();
      expect(isResolved, isTrue);
      expect(resolvedState!.turnNumber, hostState.turnNumber + 2);
      // 決着していない対戦の同期は残り時間のタイマーを持ち続けるため、テストの終わりの前に止める
      hostSession.dispose();
    });

    testWidgets('片方が操作をやめた対戦は、サーバーの期限の後に、行動を出した側の勝ち・やめた側の負けで 2 人の端末とも終わる', (
      tester,
    ) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      final guestSession = sessionOf(server: server, player: guest)..start();
      addTearDown(hostSession.dispose);
      addTearDown(guestSession.dispose);
      PvpBattleInterruption? hostInterruption;
      PvpBattleInterruption? guestInterruption;
      hostSession.interruption
          .then((interruption) => hostInterruption = interruption)
          .ignore();
      guestSession.interruption
          .then((interruption) => guestInterruption = interruption)
          .ignore();
      BattleState? hostNextState;
      var hostAdvanceCompleted = false;
      hostSession
          .advance(
            state: startStateOf(player: host, opponent: guest),
            playerAction: const UseMoveAction(moveID: 'fire_1'),
          )
          .then((state) {
            hostNextState = state;
            hostAdvanceCompleted = true;
          })
          .ignore();

      // 端末の残り時間が 0 になると時間切れを頼むが、サーバーの期限の前は対戦が終わらない
      await tester.pump(const Duration(seconds: 59));
      expect(server.timeoutClaimUids, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(server.timeoutClaimUids, unorderedEquals([host.uid, guest.uid]));
      expect(server.battle!.status, PvpBattleStatus.active);
      expect(hostInterruption, isNull);

      // サーバーの期限を過ぎた後の頼み直しで終わる
      server.isTurnDeadlinePassed = true;
      await tester.pump(const Duration(seconds: 3));
      expect(server.battle!.status, PvpBattleStatus.finished);
      expect(server.battle!.winnerUid, host.uid);
      expect(hostInterruption, (winner: BattleSideID.player));
      expect(guestInterruption, (winner: BattleSideID.opponent));
      expect(hostAdvanceCompleted, isTrue);
      expect(hostNextState, isNull);

      // 終わった後は時間切れを頼み続けない
      final claimCount = server.timeoutClaimUids.length;
      await tester.pump(const Duration(seconds: 30));
      expect(server.timeoutClaimUids, hasLength(claimCount));
    });

    testWidgets('2 人とも行動を出さなかった対戦は、サーバーの期限の後に勝敗を付けずに終わる', (tester) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      PvpBattleInterruption? hostInterruption;
      var isInterrupted = false;
      hostSession.interruption.then((interruption) {
        hostInterruption = interruption;
        isInterrupted = true;
      }).ignore();

      server.isTurnDeadlinePassed = true;
      await tester.pump(const Duration(seconds: 59));
      expect(isInterrupted, isFalse);
      await tester.pump(const Duration(seconds: 1));

      expect(server.battle!.status, PvpBattleStatus.noContest);
      expect(isInterrupted, isTrue);
      expect(hostInterruption, (winner: null));
    });

    testWidgets('残り時間は 1 秒ずつ減って 0 で止まり、ターンが公開されると 1 ターンの秒数に戻る', (tester) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      expect(hostSession.remainingSeconds.value, 60);

      await tester.pump(const Duration(seconds: 1));
      expect(hostSession.remainingSeconds.value, 59);
      await tester.pump(const Duration(seconds: 44));
      expect(hostSession.remainingSeconds.value, 15);

      hostSession
          .advance(
            state: startStateOf(player: host, opponent: guest),
            playerAction: const UseMoveAction(moveID: 'fire_1'),
          )
          .ignore();
      server.submitAction(
        uid: guest.uid,
        round: 0,
        action: const UseMoveAction(moveID: 'paper_1'),
      );
      await tester.pump();
      expect(hostSession.remainingSeconds.value, 60);

      await tester.pump(const Duration(seconds: 90));
      expect(hostSession.remainingSeconds.value, 0);
      hostSession.dispose();
    });

    testWidgets('相手にブロックされた対戦と、相手のアカウントの削除で消えた対戦は、勝敗を付けずに終わる', (tester) async {
      for (final finish in [
        (FakePvpBattleServer server) => server.finishByBlock(),
        (FakePvpBattleServer server) => server.deleteBattle(),
      ]) {
        final server = matchedServer();
        final hostSession = sessionOf(server: server, player: host)..start();
        PvpBattleInterruption? hostInterruption;
        var isInterrupted = false;
        hostSession.interruption.then((interruption) {
          hostInterruption = interruption;
          isInterrupted = true;
        }).ignore();
        await tester.pump();
        expect(isInterrupted, isFalse);

        finish(server);
        await tester.pump();

        expect(isInterrupted, isTrue);
        expect(hostInterruption, (winner: null));
        hostSession.dispose();
      }
    });

    testWidgets('自分の計算では決着していないのに相手が勝者を報告した時は、決着していないと報告して勝敗を付けずに終わる', (
      tester,
    ) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      PvpBattleInterruption? hostInterruption;
      var isInterrupted = false;
      hostSession.interruption.then((interruption) {
        hostInterruption = interruption;
        isInterrupted = true;
      }).ignore();

      server.reportResult(uid: guest.uid, winnerUid: guest.uid);
      await tester.pump();

      expect(server.reportCalls.last, (uid: host.uid, winnerUid: null));
      expect(server.battle!.status, PvpBattleStatus.noContest);
      expect(server.battle!.finishReason, PvpFinishReason.mismatch);
      expect(isInterrupted, isTrue);
      expect(hostInterruption, (winner: null));
    });

    testWidgets('自分の計算で決着した後に相手の報告が届いても、途中で終わった扱いにしない', (tester) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      var isInterrupted = false;
      hostSession.interruption.then((_) => isInterrupted = true).ignore();
      // 後から来た側が選べない行動を出し、先に待っていた側の計算が自分の勝ちで決着する
      final hostNext = hostSession.advance(
        state: startStateOf(player: host, opponent: guest),
        playerAction: const UseMoveAction(moveID: 'fire_1'),
      );
      server.submitAction(
        uid: guest.uid,
        round: 0,
        action: const UseMoveAction(moveID: 'water_1'),
      );
      await tester.pump();
      expect((await hostNext)!.winner, BattleSideID.player);

      server.reportResult(uid: guest.uid, winnerUid: host.uid);
      await tester.pump(const Duration(seconds: 120));

      expect(isInterrupted, isFalse);
      expect(server.timeoutClaimUids, isEmpty);
    });

    testWidgets('行動を出す呼び出しが失敗した時は、通るまでやり直す', (tester) async {
      final server = matchedServer()..submitError = StateError('通信に失敗');
      final hostSession = sessionOf(server: server, player: host)..start();
      addTearDown(hostSession.dispose);
      final hostState = startStateOf(player: host, opponent: guest);
      final hostNext = hostSession.advance(
        state: hostState,
        playerAction: const UseMoveAction(moveID: 'fire_1'),
      );
      await tester.pump();
      expect(server.submitCalls, hasLength(1));

      server.submitError = null;
      await tester.pump(const Duration(seconds: 3));
      expect(server.submitCalls, hasLength(2));
      server.submitAction(
        uid: guest.uid,
        round: 0,
        action: const UseMoveAction(moveID: 'paper_1'),
      );
      await tester.pump();

      expect((await hostNext)!.turnNumber, hostState.turnNumber + 2);
      hostSession.dispose();
    });

    testWidgets('止めた後は、公開を待っていた行動を進めず、時間切れも頼まない', (tester) async {
      final server = matchedServer();
      final hostSession = sessionOf(server: server, player: host)..start();
      final hostNext = hostSession.advance(
        state: startStateOf(player: host, opponent: guest),
        playerAction: const UseMoveAction(moveID: 'fire_1'),
      );
      await tester.pump();

      hostSession.dispose();
      expect(await hostNext, isNull);
      await tester.pump(const Duration(seconds: 120));
      expect(server.timeoutClaimUids, isEmpty);
    });
  });

  group('pvpBattleRecorder', () {
    testWidgets('開始の記録は呼ばずに対戦の ID を返し、完了の記録は勝者の uid を報告してからレベルを記録する', (
      tester,
    ) async {
      for (final (winner, winnerUid) in [
        (BattleSideID.player, guest.uid),
        (BattleSideID.opponent, host.uid),
      ]) {
        final server = matchedServer();
        final calls = RecordedBattleCalls();
        final recorder = pvpBattleRecorder(
          base: fakeBattleRecorder(
            calls: calls,
            startBattleRecord: () =>
                throw StateError('開始の記録は Functions が作るため呼ばない'),
            recordedLevels: const {'sample-noton': 3},
          ),
          // 後から来た側の端末
          session: sessionOf(server: server, player: guest),
        );

        expect(
          await recorder.startBattleRecord(partyMonsterIDs: ['sample-noton']),
          FakePvpBattleServer.battleID,
        );
        expect(calls.startedPartyMonsterIDs, isEmpty);
        expect(
          await recorder.completeBattleRecord(
            battleID: FakePvpBattleServer.battleID,
            participantMonsterIDs: ['sample-noton'],
            winner: winner,
            turnCount: 4,
          ),
          {'sample-noton': 3},
        );
        expect(server.reportCalls, [(uid: guest.uid, winnerUid: winnerUid)]);
        expect(
          calls.completedBattles.single.battleID,
          FakePvpBattleServer.battleID,
        );
        expect(calls.completedBattles.single.participantMonsterIDs, [
          'sample-noton',
        ]);
        expect(calls.completedBattles.single.winner, winner);
        expect(calls.completedBattles.single.turnCount, 4);
      }
    });

    testWidgets('勝者の報告が失敗した時は、レベルを記録せずにその失敗を投げる', (tester) async {
      final calls = RecordedBattleCalls();
      final session = PvpBattleSession(
        client: signedOutPvpBattleClient(),
        battle: matchedServer().battle!,
        playerUid: host.uid,
        definitions: definitions,
      );

      await expectLater(
        pvpBattleRecorder(
          base: fakeBattleRecorder(
            calls: calls,
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          session: session,
        ).completeBattleRecord(
          battleID: FakePvpBattleServer.battleID,
          participantMonsterIDs: ['sample-mugmon'],
          winner: BattleSideID.player,
          turnCount: 2,
        ),
        throwsStateError,
      );
      expect(calls.completedBattles, isEmpty);
    });
  });
}
