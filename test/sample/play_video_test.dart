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
