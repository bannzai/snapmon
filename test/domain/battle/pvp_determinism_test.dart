import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_mirror.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/battle/status_condition.dart';
import 'package:snapmon/domain/monster/monster_state.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

import '../../battle_state_description.dart';
import '../../sample_data_fixture.dart';

// 人との対戦 (issue #386) で 2 人の端末が同じ結果を出すための、バトルの計算の土台:
// 陣営の入れ替え (mirrorBattleState)、手持ちを残した決着 (finishBattleByForfeit)、選べる行動の判定 (isSelectableAction)、計算の版 (pvpBattleCalculationVersion)。
void main() {
  final sampleData = loadSampleDataFixture();
  final master = sampleData.definitions;

  /// 見本のモンスター [monsterIDs] を、見本のレベルのまま補正なしでバトルに出す手持ちにする。
  List<BattleMonster> members({required List<String> monsterIDs}) => [
    for (final monsterID in monsterIDs)
      prepareBattleMonster(
        definition: sampleData.monsterByID(monsterID: monsterID).definition,
        level: sampleData.monsterByID(monsterID: monsterID).level,
        experience: 0,
        actionCardMoveIDs: const [],
        selectedMoveIDs: null,
        master: master,
        maximumHitPointsPercent: 100,
      ),
  ];

  /// 利用者が [playerMonsterIDs]、相手が [opponentMonsterIDs] の、補正なしの対戦の最初の状態。
  BattleState start({
    required List<String> playerMonsterIDs,
    required List<String> opponentMonsterIDs,
  }) => startBattle(
    playerMembers: members(monsterIDs: playerMonsterIDs),
    opponentMembers: members(monsterIDs: opponentMonsterIDs),
    randomSeed: 20261119,
    battleDate: DateTime(2026, 11, 19),
    opponentDamagePercent: 100,
  );

  /// [state] から、両陣営が CPU の規則で選んだ行動で決着まで進めた状態。
  BattleState playUntilFinished({required BattleState state}) {
    var current = state;
    // 300 ラウンド: 手持ち 2 体ずつの対戦が決着する数より十分多く、決着しない不具合でテストが止まらない上限
    for (var round = 0; round < 300 && current.winner == null; round++) {
      current = advanceRound(
        state: current,
        playerAction: chooseCpuAction(
          state: current,
          side: BattleSideID.player,
          master: master,
        ),
        opponentAction: chooseCpuAction(
          state: current,
          side: BattleSideID.opponent,
          master: master,
        ),
        master: master,
      );
    }
    return current;
  }

  /// [party] の場のモンスターの状態を [state] に替えた陣営。
  BattleParty withActiveState({
    required BattleParty party,
    required MonsterState state,
  }) => BattleParty(
    members: [
      for (final (index, member) in party.members.indexed)
        index == party.activeMemberIndex
            ? BattleMonster(
                definition: member.definition,
                state: state,
                maximumHitPointsPercent: member.maximumHitPointsPercent,
              )
            : member,
    ],
    activeMemberIndex: party.activeMemberIndex,
  );

  group('mirrorBattleState', () {
    final finished = playUntilFinished(
      state: start(
        playerMonsterIDs: ['sample-mugmon', 'sample-keybon'],
        opponentMonsterIDs: ['sample-noton', 'sample-slippan'],
      ),
    );

    test('2 つの陣営の手持ち・勝った陣営・ログの陣営を入れ替える', () {
      final mirrored = mirrorBattleState(state: finished);

      expect(finished.winner, isNotNull);
      expect(mirrored.winner, otherSide(side: finished.winner!));
      expect(
        [for (final member in mirrored.player.members) member.definition.id],
        ['sample-noton', 'sample-slippan'],
      );
      expect(
        [for (final member in mirrored.opponent.members) member.definition.id],
        ['sample-mugmon', 'sample-keybon'],
      );
      expect(
        mirrored.player.activeMemberIndex,
        finished.opponent.activeMemberIndex,
      );
      // 技を使った陣営・倒れた陣営・レベルが上がった陣営が、どのログでも反対の陣営になる
      expect(mirrored.events, hasLength(finished.events.length));
      for (final (index, event) in finished.events.indexed) {
        switch ((event, mirrored.events[index])) {
          case (
            MoveUsedEvent(:final attackerSide, :final damage),
            MoveUsedEvent(
              attackerSide: final mirroredAttackerSide,
              damage: final mirroredDamage,
            ),
          ):
            expect(mirroredAttackerSide, otherSide(side: attackerSide));
            expect(mirroredDamage, damage);
          case (
            MonsterFaintedEvent(:final side, :final monsterID),
            MonsterFaintedEvent(
              side: final mirroredSide,
              monsterID: final mirroredMonsterID,
            ),
          ):
            expect(mirroredSide, otherSide(side: side));
            expect(mirroredMonsterID, monsterID);
          case (
            LevelUpEvent(:final side),
            LevelUpEvent(side: final mirroredSide),
          ):
            expect(mirroredSide, otherSide(side: side));
          case (
            BattleFinishedEvent(:final winner),
            BattleFinishedEvent(winner: final mirroredWinner),
          ):
            expect(mirroredWinner, otherSide(side: winner));
          case (final original, final mirroredEvent):
            expect(mirroredEvent.runtimeType, original.runtimeType);
        }
      }
      // 決着した対戦には、技・倒れた・レベルアップ・決着のログが必ずある (上の確認が 1 件も通らずに終わっていない)
      expect(finished.events.whereType<MoveUsedEvent>(), isNotEmpty);
      expect(finished.events.whereType<MonsterFaintedEvent>(), isNotEmpty);
      expect(finished.events.whereType<LevelUpEvent>(), isNotEmpty);
    });

    test('状態異常・場の効果・行動の失敗・交代・能力の変化のログも、利用者の陣営のものは相手の陣営のものになる', () {
      final mirroredEvents = mirrorBattleState(
        state: BattleState(
          player: finished.player,
          opponent: finished.opponent,
          turnNumber: finished.turnNumber,
          randomState: finished.randomState,
          events: const [
            MoveUsedEvent(
              turnNumber: 1,
              attackerSide: BattleSideID.player,
              attackerMonsterID: 'sample-mugmon',
              moveID: null,
              typeMultiplier: 1,
              damage: 0,
              defenderRemainingHitPoints: 10,
              specialEffect: null,
              statModifierChanges: [
                StatModifierChange(
                  side: BattleSideID.player,
                  statKind: StatKind.attack,
                  previousPercent: 100,
                  newPercent: 150,
                ),
                StatModifierChange(
                  side: BattleSideID.opponent,
                  statKind: StatKind.defense,
                  previousPercent: 100,
                  newPercent: 50,
                ),
              ],
              recoveredHitPoints: 0,
              attackerRemainingHitPoints: 10,
              replacedMoveID: null,
              isOneHitKnockout: false,
              selfDestructed: false,
            ),
            ActionFailedEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              monsterID: 'sample-mugmon',
              moveID: null,
              reason: ActionFailureReason.missed,
            ),
            StatusConditionInflictedEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              monsterID: 'sample-mugmon',
              kind: StatusConditionKind.poison,
              stackCount: 1,
              replacedKind: null,
              cursedStatKind: null,
            ),
            StatusConditionCuredEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              monsterID: 'sample-mugmon',
              kinds: [StatusConditionKind.poison],
              cause: StatusConditionCureCause.expired,
            ),
            StatusConditionDamageEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              monsterID: 'sample-mugmon',
              kind: StatusConditionKind.poison,
              damage: 3,
              remainingHitPoints: 7,
            ),
            FieldEffectStartedEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              kind: FieldEffectKind.statShuffle,
            ),
            MonsterSwitchedInEvent(
              turnNumber: 1,
              side: BattleSideID.player,
              monsterID: 'sample-keybon',
              withdrawnMonsterID: 'sample-mugmon',
            ),
          ],
          winner: null,
          battleDate: finished.battleDate,
          field: finished.field,
          opponentDamagePercent: finished.opponentDamagePercent,
        ),
      ).events;

      expect(
        [
          for (final change
              in (mirroredEvents[0] as MoveUsedEvent).statModifierChanges)
            (change.side, change.statKind, change.newPercent),
        ],
        [
          (BattleSideID.opponent, StatKind.attack, 150),
          (BattleSideID.player, StatKind.defense, 50),
        ],
      );
      final failed = mirroredEvents[1] as ActionFailedEvent;
      expect(failed.side, BattleSideID.opponent);
      expect(failed.monsterID, 'sample-mugmon');
      expect(failed.reason, ActionFailureReason.missed);
      final inflicted = mirroredEvents[2] as StatusConditionInflictedEvent;
      expect(inflicted.side, BattleSideID.opponent);
      expect(inflicted.kind, StatusConditionKind.poison);
      expect(inflicted.stackCount, 1);
      final cured = mirroredEvents[3] as StatusConditionCuredEvent;
      expect(cured.side, BattleSideID.opponent);
      expect(cured.kinds, [StatusConditionKind.poison]);
      expect(cured.cause, StatusConditionCureCause.expired);
      final conditionDamage = mirroredEvents[4] as StatusConditionDamageEvent;
      expect(conditionDamage.side, BattleSideID.opponent);
      expect(conditionDamage.damage, 3);
      expect(conditionDamage.remainingHitPoints, 7);
      final fieldStarted = mirroredEvents[5] as FieldEffectStartedEvent;
      expect(fieldStarted.side, BattleSideID.opponent);
      expect(fieldStarted.kind, FieldEffectKind.statShuffle);
      final switchedIn = mirroredEvents[6] as MonsterSwitchedInEvent;
      expect(switchedIn.side, BattleSideID.opponent);
      expect(switchedIn.monsterID, 'sample-keybon');
      expect(switchedIn.withdrawnMonsterID, 'sample-mugmon');
    });

    test('2 回入れ替えると元の状態に戻る', () {
      expect(
        describeBattleState(
          state: mirrorBattleState(state: mirrorBattleState(state: finished)),
        ),
        describeBattleState(state: finished),
      );
    });

    test('入れ替えた状態は元の状態と違う (入れ替えが何もしない実装では通らない)', () {
      expect(
        describeBattleState(state: mirrorBattleState(state: finished)),
        isNot(describeBattleState(state: finished)),
      );
    });

    test('利用者と相手を逆にして始めた最初の状態は、元の最初の状態の陣営を入れ替えたものと同じ', () {
      expect(
        describeBattleState(
          state: start(
            playerMonsterIDs: ['sample-noton', 'sample-slippan'],
            opponentMonsterIDs: ['sample-mugmon', 'sample-keybon'],
          ),
        ),
        describeBattleState(
          state: mirrorBattleState(
            state: start(
              playerMonsterIDs: ['sample-mugmon', 'sample-keybon'],
              opponentMonsterIDs: ['sample-noton', 'sample-slippan'],
            ),
          ),
        ),
      );
    });
  });

  group('finishBattleByForfeit', () {
    final started = start(
      playerMonsterIDs: ['sample-mugmon', 'sample-keybon'],
      opponentMonsterIDs: ['sample-noton'],
    );

    test('手持ちを残したまま渡した陣営の勝ちで終え、両陣営の場に出たモンスターだけレベルを 1 上げる', () {
      final finished = finishBattleByForfeit(
        state: started,
        winner: BattleSideID.opponent,
      );

      expect(finished.winner, BattleSideID.opponent);
      expect(finished.player.isDefeated, isFalse);
      // sample-mugmon は Lv.7、場に出ていない sample-keybon は Lv.3、相手の sample-noton は Lv.2 (assets/samples/sample_monsters.json)
      expect(
        [for (final member in finished.player.members) member.state.level],
        [8, 3],
      );
      expect(
        [for (final member in finished.player.members) member.state.experience],
        [1, 0],
      );
      expect(finished.opponent.members.single.state.level, 3);
      expect(
        [
          for (final event in finished.events.whereType<LevelUpEvent>())
            (event.side, event.monsterID, event.newLevel),
        ],
        [
          (BattleSideID.player, 'sample-mugmon', 8),
          (BattleSideID.opponent, 'sample-noton', 3),
        ],
      );
      final finishedEvent = finished.events.last as BattleFinishedEvent;
      expect(finishedEvent.winner, BattleSideID.opponent);
      expect(finishedEvent.turnNumber, started.turnNumber);
    });

    test('ラウンドを解決しないため、乱数とターンの番号と HP を進めない', () {
      final finished = finishBattleByForfeit(
        state: started,
        winner: BattleSideID.player,
      );

      expect(finished.randomState, started.randomState);
      expect(finished.turnNumber, started.turnNumber);
      expect(
        finished.player.activeMember.state.currentHitPoints,
        started.player.activeMember.state.currentHitPoints,
      );
    });

    test('ラウンドを進めた後は、交代で場に出たモンスターのレベルも上げる', () {
      expect(
        [
          for (final member in finishBattleByForfeit(
            state: advanceRound(
              state: started,
              playerAction: const SwitchMonsterAction(memberIndex: 1),
              opponentAction: chooseCpuAction(
                state: started,
                side: BattleSideID.opponent,
                master: master,
              ),
              master: master,
            ),
            winner: BattleSideID.player,
          ).player.members)
            member.state.level,
        ],
        [8, 4],
      );
    });

    test('レベルの上限のモンスターは上限のまま、経験だけ増える', () {
      final finished = finishBattleByForfeit(
        state: BattleState(
          player: withActiveState(
            party: started.player,
            state: started.player.activeMember.state.copyWith(
              level: maximumLevel,
            ),
          ),
          opponent: started.opponent,
          turnNumber: started.turnNumber,
          randomState: started.randomState,
          events: started.events,
          winner: null,
          battleDate: started.battleDate,
          field: null,
          opponentDamagePercent: 100,
        ),
        winner: BattleSideID.player,
      );

      expect(finished.player.activeMember.state.level, maximumLevel);
      expect(finished.player.activeMember.state.experience, 1);
    });

    test('決着済みの状態には例外を投げる', () {
      expect(
        () => finishBattleByForfeit(
          state: finishBattleByForfeit(
            state: started,
            winner: BattleSideID.player,
          ),
          winner: BattleSideID.opponent,
        ),
        throwsStateError,
      );
    });
  });

  group('isSelectableAction', () {
    final started = start(
      playerMonsterIDs: ['sample-mugmon', 'sample-keybon'],
      opponentMonsterIDs: ['sample-noton'],
    );

    /// 陣営 [party] の場のモンスターが [action] を選べるか。
    bool isSelectable({
      required BattleAction action,
      required BattleParty party,
    }) => isSelectableAction(party: party, action: action, master: master);

    test('開放済みで PP の残っている技は選べ、開放前の技・覚えない技・PP が 0 の技は選べない', () {
      // sample-mugmon (Lv.7) は fire_1 を Lv.1 で、fire_2 を Lv.15 で覚える。water_1 は覚えない
      expect(
        isSelectable(
          party: started.player,
          action: const UseMoveAction(moveID: 'fire_1'),
        ),
        isTrue,
      );
      expect(
        isSelectable(
          party: started.player,
          action: const UseMoveAction(moveID: 'fire_2'),
        ),
        isFalse,
      );
      expect(
        isSelectable(
          party: started.player,
          action: const UseMoveAction(moveID: 'water_1'),
        ),
        isFalse,
      );
      expect(
        isSelectable(
          action: const UseMoveAction(moveID: 'fire_1'),
          party: withActiveState(
            party: started.player,
            state: started.player.activeMember.state.copyWith(
              remainingPowerPoints: {
                ...started.player.activeMember.state.remainingPowerPoints,
                'fire_1': 0,
              },
            ),
          ),
        ),
        isFalse,
      );
    });

    test('わるあがきは、使える攻撃技が残っている間は選べず、どの技の PP も無くなると選べる', () {
      expect(
        isSelectable(party: started.player, action: const StruggleAction()),
        isFalse,
      );
      expect(
        isSelectable(
          action: const StruggleAction(),
          party: withActiveState(
            party: started.player,
            state: started.player.activeMember.state.copyWith(
              remainingPowerPoints: {
                for (final moveID
                    in started
                        .player
                        .activeMember
                        .state
                        .remainingPowerPoints
                        .keys)
                  moveID: 0,
              },
            ),
          ),
        ),
        isTrue,
      );
    });

    test('交代は、控えの倒れていないモンスターにだけできる', () {
      expect(
        isSelectable(
          party: started.player,
          action: const SwitchMonsterAction(memberIndex: 1),
        ),
        isTrue,
      );
      // 場に出ているモンスター・手持ちに無い位置
      expect(
        isSelectable(
          party: started.player,
          action: const SwitchMonsterAction(memberIndex: 0),
        ),
        isFalse,
      );
      expect(
        isSelectable(
          party: started.player,
          action: const SwitchMonsterAction(memberIndex: 2),
        ),
        isFalse,
      );
      expect(
        isSelectable(
          party: started.player,
          action: const SwitchMonsterAction(memberIndex: -1),
        ),
        isFalse,
      );
      // 倒れている控え
      expect(
        isSelectable(
          action: const SwitchMonsterAction(memberIndex: 1),
          party: BattleParty(
            members: [
              started.player.members[0],
              BattleMonster(
                definition: started.player.members[1].definition,
                state: started.player.members[1].state.copyWith(
                  currentHitPoints: 0,
                ),
                maximumHitPointsPercent: 100,
              ),
            ],
            activeMemberIndex: 0,
          ),
        ),
        isFalse,
      );
    });
  });

  group('pvpBattleCalculationVersion', () {
    // バトルの計算を変えて下の値が変わった時は、人との対戦で版の違う端末どうしが組み合わされて結果が食い違わないよう
    // pvpBattleCalculationVersion (lib/domain/battle/battle_engine.dart) を上げ、新しい値に書き換える。
    test('版 1 の計算は、固定した手持ち・乱数の種・行動の決め方から同じ結果を出す', () {
      expect(pvpBattleCalculationVersion, 1);
      final finished = playUntilFinished(
        state: start(
          playerMonsterIDs: ['sample-mugmon', 'sample-keybon'],
          opponentMonsterIDs: ['sample-noton', 'sample-slippan'],
        ),
      );
      expect(
        [
          'winner=${finished.winner?.name}',
          'turnNumber=${finished.turnNumber}',
          'eventCount=${finished.events.length}',
          'randomState=${finished.randomState}',
          'playerHitPoints=${[for (final member in finished.player.members) member.state.currentHitPoints]}',
          'opponentHitPoints=${[for (final member in finished.opponent.members) member.state.currentHitPoints]}',
        ].join(' '),
        pvpBattleCalculationVersion1BattleFingerprint,
      );
    });
  });
}

/// 版 1 のバトルの計算で、上のテストの固定した対戦を決着まで進めた結果
/// (2026-11-19 の flutter-ci の実行 https://github.com/bannzai/snapmon/actions/runs/44505632319 で得た値)。
const String pvpBattleCalculationVersion1BattleFingerprint =
    'winner=player turnNumber=11 eventCount=16 randomState=2216667923 '
    'playerHitPoints=[8, 16] opponentHitPoints=[0, 0]';
