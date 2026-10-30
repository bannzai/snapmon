import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/first_battle.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';

import '../../card_sharer_fixture.dart';
import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 見本のモンスター [monsterId] に、切り出した画像 [artPath] を持たせた 1 体。
  OwnedMonster monsterWithArt({
    required String monsterId,
    required String artPath,
  }) => ownedMonsterWithArt(
    monster: sampleData.monsterById(monsterId: monsterId),
    artPath: artPath,
    sourcePhotoReference: 'users/uid-1/photos/$monsterId',
  );

  /// 手持ちが [monster] 1 体の他のユーザー [opponentUid]。
  PvpOpponent pvpOpponentWith({
    required String opponentUid,
    required OwnedMonster monster,
  }) => PvpOpponent(
    opponentUid: opponentUid,
    displayName: opponentUid,
    monsters: [monster],
  );

  /// 2 × 2 の [color] 一色の画像。切り出した画像の代わりに使う。
  Future<ui.Image> solidImage({required ui.Color color}) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = color);
    return recorder.endRecording().toImage(2, 2);
  }

  test(
    '候補の先頭の相手の定義を読めない時は、例外にせず CPU トレーナーと戦う (もう一度試しても同じ相手で止まり続けないため)',
    () async {
      // 本番と同じく、生まれたモンスターを手持ちに入れた後の図鑑で相手を決める (CPU の手持ちのレベルを自分の手持ちに合わせるため)
      final dexStore = DexStore(definitions: sampleData.definitions)
        ..applyServerSnapshot(
          monsters: [sampleData.monsterById(monsterId: 'sample-mugmon')],
          partyMonsterIds: ['sample-mugmon'],
          definitions: null,
        );
      final opponent = await prepareFirstBattleOpponent(
        dexStore: dexStore,
        pvpClient: PvpClient(
          // 候補が 2 人いると先頭を選ぶ (chooseFirstBattleOpponent)
          fetchOpponents: () async => [
            for (final index in [1, 2])
              PvpOpponent(
                opponentUid: 'opponent-uid-$index',
                displayName: 'ろうそくや $index',
                monsters: [
                  generatedWaxMonster(monsterId: 'opponent-wax-$index'),
                ],
              ),
          ],
          fetchDefinitions: ({required base, required definitionIds}) =>
              throw Exception('permission-denied'),
          reportMonster:
              ({
                required monsterOwnerUid,
                required monsterId,
                required reason,
              }) => throw StateError('reportMonster は呼ばない'),
          blockUser: ({required blockedUid}) =>
              throw StateError('blockUser は呼ばない'),
          fetchBattleRecord: () async => null,
          fetchDisplayName: () async => null,
          updateDisplayName: ({required displayName}) async => displayName,
        ),
        sampleData: sampleData,
        randomSeed: 1,
        loadArtImage: ({required artPath}) =>
            throw StateError('$artPath を読めない'),
      );
      expect(opponent.opponentKind, BattleOpponentKind.cpu);
      expect(opponent.pvpOpponent, isNull);
      expect(opponent.opponentName, startsWith('CPU '));
    },
  );

  test('自分の手持ちと同じ絵 (同じパスか同じ画素) のモンスターを持つ候補を飛ばし、読めない絵は同じと見なさない', () async {
    final colorsByArtPath = {
      'monsters/mine/art.png': const ui.Color(0xFFC6F432),
      // 別のアカウントで同じ写真から生まれたモンスター (パスは違うが画素が同じ)
      'monsters/same-photo/art.png': const ui.Color(0xFFC6F432),
      'monsters/other/art.png': const ui.Color(0xFFFF6B6B),
    };
    final candidates = await excludeOpponentsWithSameArt(
      pvpOpponents: [
        pvpOpponentWith(
          opponentUid: 'uid-same-pixels',
          monster: monsterWithArt(
            monsterId: 'sample-keybon',
            artPath: 'monsters/same-photo/art.png',
          ),
        ),
        pvpOpponentWith(
          opponentUid: 'uid-same-path',
          monster: monsterWithArt(
            monsterId: 'sample-noton',
            artPath: 'monsters/mine/art.png',
          ),
        ),
        pvpOpponentWith(
          opponentUid: 'uid-unreadable',
          monster: monsterWithArt(
            monsterId: 'sample-ringora',
            artPath: 'monsters/unreadable/art.png',
          ),
        ),
        pvpOpponentWith(
          opponentUid: 'uid-other',
          monster: monsterWithArt(
            monsterId: 'sample-slippan',
            artPath: 'monsters/other/art.png',
          ),
        ),
      ],
      playerParty: [
        monsterWithArt(
          monsterId: 'sample-mugmon',
          artPath: 'monsters/mine/art.png',
        ),
      ],
      loadArtImage: ({required artPath}) async {
        final color = colorsByArtPath[artPath];
        return color == null
            ? throw StateError('$artPath を読めない')
            : solidImage(color: color);
      },
    );
    expect(candidates.map((candidate) => candidate.opponentUid), [
      'uid-unreadable',
      'uid-other',
    ]);
  });

  testWidgets(
    '絵の読み込みが終わらない時は、1 枚ごとに 5 秒の上限の後に読めない絵と同じく扱って候補を返し、遅れて届いた絵を dispose する',
    (tester) async {
      final playerArtImage = (await tester.runAsync(
        () => solidImage(color: const ui.Color(0xFFC6F432)),
      ))!;
      final lateArtImages = (await tester.runAsync(
        () => Future.wait([
          solidImage(color: const ui.Color(0xFFC6F432)),
          solidImage(color: const ui.Color(0xFFC6F432)),
        ]),
      ))!;
      final hangingLoads = <String, Completer<ui.Image>>{};
      List<PvpOpponent>? candidates;
      unawaited(
        excludeOpponentsWithSameArt(
          pvpOpponents: [
            pvpOpponentWith(
              opponentUid: 'uid-hanging',
              monster: monsterWithArt(
                monsterId: 'sample-keybon',
                artPath: 'monsters/opponent-hanging/art.png',
              ),
            ),
          ],
          playerParty: [
            monsterWithArt(
              monsterId: 'sample-mugmon',
              artPath: 'monsters/mine/art.png',
            ),
            monsterWithArt(
              monsterId: 'sample-noton',
              artPath: 'monsters/mine-hanging/art.png',
            ),
          ],
          loadArtImage: ({required artPath}) =>
              artPath == 'monsters/mine/art.png'
              ? Future.value(playerArtImage)
              : (hangingLoads[artPath] = Completer<ui.Image>()).future,
        ).then((value) => candidates = value),
      );
      // 自分の 2 枚目と候補の絵が 1 枚ずつ順に上限まで待つため、10 秒で返る
      await tester.pump(const Duration(seconds: 9));
      expect(candidates, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(candidates?.map((candidate) => candidate.opponentUid), [
        'uid-hanging',
      ]);
      expect(hangingLoads.keys, [
        'monsters/mine-hanging/art.png',
        'monsters/opponent-hanging/art.png',
      ]);
      expect(playerArtImage.debugDisposed, isTrue);

      for (final (index, hangingLoad) in hangingLoads.values.indexed) {
        hangingLoad.complete(lateArtImages[index]);
      }
      await tester.pump();
      for (final lateArtImage in lateArtImages) {
        expect(lateArtImage.debugDisposed, isTrue);
      }
    },
  );

  test('自分の手持ちと同じ見本のモンスターを持つ CPU トレーナーを除き、全員が除かれる時は全員を残す', () {
    final cpuTrainerIds = excludeCpuTrainersWithSameArt(
      sampleData: sampleData,
      playerParty: [sampleData.monsterById(monsterId: 'sample-mugmon')],
    ).map((cpuTrainer) => cpuTrainer.id);
    expect(cpuTrainerIds, hasLength(sampleData.cpuTrainers.length - 1));
    for (final cpuTrainer in sampleData.cpuTrainers) {
      expect(
        cpuTrainerIds.contains(cpuTrainer.id),
        !cpuTrainer.monsterIds.contains('sample-mugmon'),
        reason: cpuTrainer.id,
      );
    }
    expect(
      excludeCpuTrainersWithSameArt(
        sampleData: sampleData,
        playerParty: sampleData.monsters,
      ),
      sampleData.cpuTrainers,
    );
  });

  group('chooseFirstBattleOpponent', () {
    final candidates = [
      for (final index in [1, 2])
        pvpOpponentWith(
          opponentUid: 'uid-$index',
          monster: sampleData.monsterById(monsterId: 'sample-keybon'),
        ),
    ];

    test('候補が 2 人以上の時は、どの seed でも先頭の候補 (平均レベルが最も近い) と戦う', () {
      for (var randomSeed = 1; randomSeed <= 50; randomSeed++) {
        expect(
          chooseFirstBattleOpponent(
            candidates: candidates,
            cpuTrainers: sampleData.cpuTrainers,
            randomSeed: randomSeed,
          ).pvpOpponent?.opponentUid,
          'uid-1',
        );
      }
    });

    test('候補が 0 人の時は、seed によって別の CPU トレーナーになる', () {
      expect(
        {
          for (var randomSeed = 1; randomSeed <= 50; randomSeed++)
            chooseFirstBattleOpponent(
              candidates: const [],
              cpuTrainers: sampleData.cpuTrainers,
              randomSeed: randomSeed,
            ).cpuTrainer.id,
        },
        {for (final cpuTrainer in sampleData.cpuTrainers) cpuTrainer.id},
      );
      expect(
        chooseFirstBattleOpponent(
          candidates: const [],
          cpuTrainers: sampleData.cpuTrainers,
          randomSeed: 7,
        ).cpuTrainer.id,
        chooseFirstBattleOpponent(
          candidates: const [],
          cpuTrainers: sampleData.cpuTrainers,
          randomSeed: 7,
        ).cpuTrainer.id,
      );
    });

    test('候補が 1 人の時は、seed によってその候補か CPU トレーナーになる', () {
      expect(
        {
          for (var randomSeed = 1; randomSeed <= 50; randomSeed++)
            chooseFirstBattleOpponent(
              candidates: candidates.take(1).toList(),
              cpuTrainers: sampleData.cpuTrainers,
              randomSeed: randomSeed,
            ).pvpOpponent?.opponentUid,
        },
        {'uid-1', null},
      );
    });
  });
}
