import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/sample/play_video.dart';

import '../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  final playVideo = sampleData.playVideo;

  group('preparePlayVideo', () {
    test(
      'ログイン中の図鑑から呼ぶと、ログインを終えてログインせずに入れる状態にし、図鑑を一緒に戦う味方だけ・手持ちを空にする',
      () async {
        var endSessionCount = 0;
        final sessionStore = SessionStore(
          startSession: () async => 'uid-1',
          endSession: () async => endSessionCount += 1,
          resumedUid: 'uid-1',
        );
        final dexStore = DexStore(definitions: sampleData.definitions)
          ..replaceAll(monsters: sampleData.monsters);
        await preparePlayVideo(
          sessionStore: sessionStore,
          dexStore: dexStore,
          sampleData: sampleData,
        );
        expect(endSessionCount, 1);
        expect(sessionStore.uid, isNull);
        expect(sessionStore.canEnterApp, isTrue);
        expect(dexStore.monsters.map((monster) => monster.definition.id), [
          'play-video-pukapukku',
        ]);
        // 手持ちが空でないと、次に写真から作っても初回の導線 (生まれてそのまま戦う) にならない
        expect(dexStore.party, isEmpty);
      },
    );

    test('2 回呼んでも図鑑と手持ちは 1 回の時と同じ', () async {
      final sessionStore = SessionStore(
        startSession: () async => 'uid-1',
        endSession: () async {},
        resumedUid: null,
      );
      final dexStore = DexStore(definitions: sampleData.definitions);
      for (var count = 0; count < 2; count++) {
        await preparePlayVideo(
          sessionStore: sessionStore,
          dexStore: dexStore,
          sampleData: sampleData,
        );
      }
      expect(dexStore.monsters.map((monster) => monster.definition.id), [
        'play-video-pukapukku',
      ]);
      expect(dexStore.party, isEmpty);
      expect(sessionStore.canEnterApp, isTrue);
    });
  });

  group('addPlayVideoCompanionToParty', () {
    /// 図鑑が [monsters]、手持ちが [partyMonsterIDs] の図鑑に足した後の、手持ちの ID の並び。
    Future<List<String>> partyMonsterIDsAfterAdding({
      required List<OwnedMonster> monsters,
      required List<String> partyMonsterIDs,
    }) async {
      final dexStore = DexStore(definitions: sampleData.definitions)
        ..applyServerSnapshot(
          monsters: monsters,
          partyMonsterIDs: partyMonsterIDs,
          definitions: null,
        );
      await addPlayVideoCompanionToParty(
        dexStore: dexStore,
        sampleData: sampleData,
      );
      return [for (final monster in dexStore.party) monster.definition.id];
    }

    final sampleMugmon = sampleData.monsterByID(monsterID: 'sample-mugmon');

    test('手持ちが撮影用のマグモンの 1 体だけで図鑑にプカプックがいれば、プカプックを 2 体目に足す', () async {
      expect(
        await partyMonsterIDsAfterAdding(
          monsters: [playVideo.companionMonster, playVideo.bornMonster],
          partyMonsterIDs: ['play-video-mugmon'],
        ),
        ['play-video-mugmon', 'play-video-pukapukku'],
      );
    });

    test('2 回呼んでも手持ちは 2 体のまま', () async {
      final dexStore = DexStore(definitions: sampleData.definitions)
        ..applyServerSnapshot(
          monsters: [playVideo.companionMonster, playVideo.bornMonster],
          partyMonsterIDs: ['play-video-mugmon'],
          definitions: null,
        );
      for (var count = 0; count < 2; count++) {
        await addPlayVideoCompanionToParty(
          dexStore: dexStore,
          sampleData: sampleData,
        );
      }
      expect(dexStore.party.map((monster) => monster.definition.id), [
        'play-video-mugmon',
        'play-video-pukapukku',
      ]);
    });

    test('図鑑にプカプックがいなければ、手持ちは撮影用のマグモンの 1 体のまま', () async {
      expect(
        await partyMonsterIDsAfterAdding(
          monsters: [playVideo.bornMonster],
          partyMonsterIDs: ['play-video-mugmon'],
        ),
        ['play-video-mugmon'],
      );
    });

    test(
      '手持ちが同じ名前の見本のマグモンの 1 体・空・撮影用のマグモンと別の 1 体の時は、図鑑にプカプックがいても足さない',
      () async {
        expect(
          await partyMonsterIDsAfterAdding(
            monsters: [playVideo.companionMonster, sampleMugmon],
            partyMonsterIDs: ['sample-mugmon'],
          ),
          ['sample-mugmon'],
        );
        expect(
          await partyMonsterIDsAfterAdding(
            monsters: [playVideo.companionMonster, playVideo.bornMonster],
            partyMonsterIDs: [],
          ),
          isEmpty,
        );
        expect(
          await partyMonsterIDsAfterAdding(
            monsters: [
              playVideo.companionMonster,
              playVideo.bornMonster,
              sampleMugmon,
            ],
            partyMonsterIDs: ['play-video-mugmon', 'sample-mugmon'],
          ),
          ['play-video-mugmon', 'sample-mugmon'],
        );
      },
    );
  });

  group('isPlayVideoParty', () {
    test('撮影用の味方の 2 体だけなら、並びがどちらでも true', () {
      expect(
        isPlayVideoParty(
          sampleData: sampleData,
          party: [playVideo.bornMonster, playVideo.companionMonster],
        ),
        isTrue,
      );
      expect(
        isPlayVideoParty(
          sampleData: sampleData,
          party: [playVideo.companionMonster, playVideo.bornMonster],
        ),
        isTrue,
      );
    });

    test('撮影用の味方の片方だけ・3 体目がいる・片方が同じ名前の見本のモンスター・空の手持ちは false', () {
      // 見本の「マグモン」(sample-mugmon) は撮影用の「マグモン」と名前が同じで別のモンスター
      final sampleMugmon = sampleData.monsterByID(monsterID: 'sample-mugmon');
      expect(sampleMugmon.definition.name, 'マグモン');
      expect(playVideo.bornMonster.definition.name, 'マグモン');
      for (final party in <List<OwnedMonster>>[
        [playVideo.bornMonster],
        [playVideo.companionMonster],
        [
          playVideo.bornMonster,
          playVideo.companionMonster,
          sampleData.monsters[1],
        ],
        [sampleMugmon, playVideo.companionMonster],
        [playVideo.bornMonster, sampleData.monsters[1]],
        [],
      ]) {
        expect(
          isPlayVideoParty(sampleData: sampleData, party: party),
          isFalse,
          reason: party.map((monster) => monster.definition.id).join(','),
        );
      }
    });
  });
}
