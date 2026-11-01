import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';
import 'package:snapmon/features/opponent/opponent_screen.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/result/monster_detail_card.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 見本のモンスター [monsterId] を、他のユーザーの [level] のモンスターにする (元の写真の参照は返らないため持たない)。
  OwnedMonster opponentMonster({
    required String monsterId,
    required int level,
  }) {
    final sample = sampleData.monsterById(monsterId: monsterId);
    return OwnedMonster(
      definition: sample.definition,
      level: level,
      artPath: null,
      definitionIds: const [],
      decoration: null,
      decorationVersion: null,
    );
  }

  final opponents = [
    PvpOpponent(
      opponentUid: 'uid-a',
      displayName: 'トレーナー 1111',
      monsters: [
        opponentMonster(monsterId: 'sample-mugmon', level: 6),
        opponentMonster(monsterId: 'sample-keybon', level: 8),
      ],
    ),
    PvpOpponent(
      opponentUid: 'uid-b',
      displayName: 'ばんざい',
      monsters: [opponentMonster(monsterId: 'sample-noton', level: 12)],
    ),
    PvpOpponent(
      opponentUid: 'uid-c',
      displayName: 'トレーナー 3333',
      monsters: [opponentMonster(monsterId: 'sample-ringora', level: 3)],
    ),
  ];

  /// [pvpClient] を使う対戦相手の画面を、手持ちを 3 体入れて iPhone の画面の大きさ (モックの 390 × 844) で開く。
  Future<void> pumpOpponentScreen({
    required WidgetTester tester,
    required PvpClient pvpClient,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OpponentScreen(
            sampleData: sampleData,
            dexStore: dexStore,
            onSelectTab: ({required tab}) {},
            onOpenSettings: () {},
            battleRecorder: fakeBattleRecorder(
              calls: RecordedBattleCalls(),
              startBattleRecord: () async => null,
              recordedLevels: const {},
            ),
            pvpClient: pvpClient,
            cardSharer: fakeCardSharer(
              calls: RecordedShareCalls(),
              artImage: null,
              shareResultStatus: ShareResultStatus.success,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// ログインしていて、他のユーザーの候補 [opponents] を返せる (けれど呼ばれない) 相手の取得。
  PvpClient signedInPvpClient({required RecordedPvpCalls calls}) =>
      fakePvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        extraDefinitions: null,
        battleRecord: (wins: 8, losses: 3),
        displayName: 'トレーナー 0001',
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
      );

  testWidgets(
    'ログインしていても他のユーザーの手持ちを読まず、CPU トレーナー 3 人と戦績だけを出し、「ほかの相手をさがす」と通報・ブロックを出さない',
    (tester) async {
      final calls = RecordedPvpCalls();
      await pumpOpponentScreen(
        tester: tester,
        pvpClient: signedInPvpClient(calls: calls),
      );
      expect(find.text('8 勝 3 敗'), findsOneWidget);
      expect(calls.fetchOpponentsCount, 0);
      for (final opponent in opponents) {
        expect(
          find.text(opponent.displayName, skipOffstage: false),
          findsNothing,
          reason: opponent.opponentUid,
        );
      }
      // 他のユーザーがいた時と同じく 3 人並べる (issue #105 の「常に 3 人出す」)
      for (final (index, cpuTrainer) in sampleData.cpuTrainers.indexed) {
        expect(
          find.byKey(
            Key('opponent-card-${cpuTrainer.id}'),
            skipOffstage: false,
          ),
          index < 3 ? findsOneWidget : findsNothing,
          reason: cpuTrainer.id,
        );
        if (index >= 3) {
          continue;
        }
        expect(find.text(cpuTrainer.name, skipOffstage: false), findsOneWidget);
        expect(cpuTrainer.name, startsWith('CPU '));
        expect(
          find.byKey(
            Key('opponent-menu-${cpuTrainer.id}'),
            skipOffstage: false,
          ),
          findsNothing,
        );
      }
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(Key('challenge-${sampleData.cpuTrainers.first.id}')),
            )
            .onPressed,
        isNotNull,
      );
      for (final key in ['reload-opponents', 'report-help']) {
        expect(
          find.byKey(Key(key), skipOffstage: false),
          findsNothing,
          reason: key,
        );
      }
      expect(find.text('ほかの相手をさがす', skipOffstage: false), findsNothing);
    },
  );

  testWidgets('CPU トレーナーのカードのレベルは、どのトレーナーも自分の手持ちの平均と同じ「Lv. N」になる', (
    tester,
  ) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
    );
    // 自分の手持ちのカードにも「Lv. N」が出るため、CPU トレーナーのカードの中だけを探す
    for (final cpuTrainer in sampleData.cpuTrainers.take(3)) {
      expect(
        find.descendant(
          of: find.byKey(
            Key('opponent-card-${cpuTrainer.id}'),
            skipOffstage: false,
          ),
          matching: find.text(
            'Lv. ${averagePartyLevel(
              party: (DexStore(definitions: sampleData.definitions)..replaceAll(monsters: sampleData.monsters)).party,
            )}',
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
        reason: cpuTrainer.id,
      );
    }
  });

  testWidgets('CPU トレーナーの手持ちの札を押すと、挑む時と同じレベルのそのモンスターの詳細をボトムシートで出す', (
    tester,
  ) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
    );
    final cpuTrainer = sampleData.cpuTrainers.first;
    final monster = sampleData.monsterById(
      monsterId: cpuTrainer.monsterIds.first,
    );
    final detailKey = Key('opponent-monster-detail-${monster.definition.id}');
    expect(find.byKey(detailKey), findsNothing);
    await tester.tap(
      find.byKey(
        Key('opponent-monster-${cpuTrainer.id}-${monster.definition.id}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(detailKey), findsOneWidget);
    final level = averagePartyLevel(
      party: (DexStore(
        definitions: sampleData.definitions,
      )..replaceAll(monsters: sampleData.monsters)).party,
    );
    final detailCard = tester.widget<MonsterDetailCard>(
      find.descendant(
        of: find.byKey(detailKey),
        matching: find.byType(MonsterDetailCard),
      ),
    );
    expect(detailCard.monster.definition.id, monster.definition.id);
    expect(detailCard.monster.level, level);
    for (final text in [monster.definition.name, 'Lv. $level', 'おぼえている技']) {
      expect(
        find.descendant(of: find.byKey(detailKey), matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('自分の手持ちの札を押すと、図鑑から開いた時と同じそのモンスターの画面を開く', (tester) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
    );
    final partyMonster = (DexStore(
      definitions: sampleData.definitions,
    )..replaceAll(monsters: sampleData.monsters)).party.first;
    await tester.tap(
      find.byKey(Key('party-monster-${partyMonster.definition.id}')),
    );
    await tester.pumpAndSettle();
    final resultScreen = tester.widget<ResultScreen>(find.byType(ResultScreen));
    expect(resultScreen.monster.definition.id, partyMonster.definition.id);
    expect(resultScreen.origin, ResultScreenOrigin.dex);
  });

  testWidgets('ログインが無い時は戦績を出さず、見本の対戦相手を出さずに CPU トレーナーを出す', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedOutPvpClient(calls: calls),
    );
    expect(find.byKey(const Key('battle-record')), findsNothing);
    expect(calls.fetchOpponentsCount, 0);
    for (final sampleOpponent in sampleData.opponents) {
      expect(
        find.text(sampleOpponent.name, skipOffstage: false),
        findsNothing,
        reason: sampleOpponent.id,
      );
    }
    expect(
      find.byKey(
        Key('opponent-card-${sampleData.cpuTrainers.first.id}'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}
