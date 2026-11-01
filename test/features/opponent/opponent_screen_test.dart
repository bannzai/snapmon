import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/first_battle.dart';
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
import 'package:snapmon/widgets/monster_parts.dart';

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
      iconPath: null,
      monsters: [
        opponentMonster(monsterId: 'sample-mugmon', level: 6),
        opponentMonster(monsterId: 'sample-keybon', level: 8),
      ],
    ),
    PvpOpponent(
      opponentUid: 'uid-b',
      displayName: 'ばんざい',
      iconPath: null,
      monsters: [opponentMonster(monsterId: 'sample-noton', level: 12)],
    ),
    PvpOpponent(
      opponentUid: 'uid-c',
      displayName: 'トレーナー 3333',
      iconPath: null,
      monsters: [opponentMonster(monsterId: 'sample-ringora', level: 3)],
    ),
  ];

  /// [pvpClient] を使う対戦相手の画面を、手持ちを 3 体入れて iPhone の画面の大きさ (モックの 390 × 844) で開く。
  /// 設定を開く操作は [onOpenSettings] を呼ぶ。
  Future<void> pumpOpponentScreen({
    required WidgetTester tester,
    required PvpClient pvpClient,
    required Future<void> Function() onOpenSettings,
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
            onOpenSettings: onOpenSettings,
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
        profile: (displayName: 'トレーナー 0001', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
      );

  testWidgets(
    'ログインしていても他のユーザーの手持ちを読まず、CPU トレーナー 3 人と戦績だけを出し、「ほかの相手をさがす」と通報・ブロックを出さない',
    (tester) async {
      final calls = RecordedPvpCalls();
      await pumpOpponentScreen(
        tester: tester,
        pvpClient: signedInPvpClient(calls: calls),
        onOpenSettings: () async {},
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
      onOpenSettings: () async {},
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
      onOpenSettings: () async {},
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
    // シートは画面の高さの 85% までで、上に残る外側を押すと閉じる
    await tester.tapAt(Offset(tester.view.physicalSize.width / 2, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(detailKey), findsNothing);
  });

  testWidgets('自分の手持ちの札を押すと、図鑑から開いた時と同じそのモンスターの画面を開く', (tester) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
      onOpenSettings: () async {},
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
      onOpenSettings: () async {},
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

  testWidgets('自分のアイコン (未登録は既定の印) と表示名を戦績と並べ、手持ちと CPU トレーナーの手持ちの札にモンスターの絵を出す', (
    tester,
  ) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
      onOpenSettings: () async {},
    );
    final playerTrainer = find.byKey(const Key('opponent-tab-player-trainer'));
    for (final text in ['トレーナー 0001', 'ト']) {
      expect(
        find.descendant(of: playerTrainer, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    final party = (DexStore(
      definitions: sampleData.definitions,
    )..replaceAll(monsters: sampleData.monsters)).party;
    final cpuTrainer = sampleData.cpuTrainers.first;
    for (final chipKey in [
      for (final monster in party) 'party-monster-${monster.definition.id}',
      for (final monsterId in cpuTrainer.monsterIds)
        'opponent-monster-${cpuTrainer.id}-$monsterId',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key(chipKey), skipOffstage: false),
          matching: find.byType(MonsterArt, skipOffstage: false),
        ),
        findsOneWidget,
        reason: chipKey,
      );
    }
  });

  testWidgets('設定を閉じたらプロフィールを読み直し、変えた表示名を出す', (tester) async {
    var displayName = 'トレーナー 0001';
    final pvpClient = signedInPvpClient(calls: RecordedPvpCalls());
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: PvpClient(
        fetchOpponents: pvpClient.fetchOpponents,
        fetchDefinitions: pvpClient.fetchDefinitions,
        reportMonster: pvpClient.reportMonster,
        blockUser: pvpClient.blockUser,
        fetchBattleRecord: pvpClient.fetchBattleRecord,
        fetchProfile: () async => (displayName: displayName, iconPath: null),
        updateDisplayName: pvpClient.updateDisplayName,
        updateIcon: pvpClient.updateIcon,
      ),
      onOpenSettings: () async => displayName = 'ばんざい',
    );
    expect(find.text('トレーナー 0001'), findsOneWidget);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    expect(find.text('ばんざい'), findsOneWidget);
    expect(find.text('トレーナー 0001'), findsNothing);
  });

  testWidgets(
    '「自動で相手を決めて戦う」は、自分の手持ちと同じ絵の見本のモンスターを持たない CPU トレーナーを選んでバトルに入り、自分と相手の名前を渡す',
    (tester) async {
      await pumpOpponentScreen(
        tester: tester,
        pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
        onOpenSettings: () async {},
      );
      await tester.tap(find.byKey(const Key('auto-match')));
      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final battleScreen = tester.widget<BattleScreen>(
        find.byType(BattleScreen),
      );
      expect(battleScreen.playerProfile, (
        displayName: 'トレーナー 0001',
        iconPath: null,
      ));
      expect(battleScreen.opponentProfile.iconPath, isNull);
      expect(battleScreen.opponentKind, BattleOpponentKind.cpu);
      // 見本の手持ち (sampleData.monsters の先頭 3 体) と同じ絵を持たない CPU トレーナーの中から選ぶ (lib/features/capture/first_battle.dart)
      final party = (DexStore(
        definitions: sampleData.definitions,
      )..replaceAll(monsters: sampleData.monsters)).party;
      final allowedTrainers = excludeCpuTrainersWithSameArt(
        sampleData: sampleData,
        playerParty: party,
      );
      final chosenTrainer = allowedTrainers.firstWhere(
        (cpuTrainer) =>
            cpuTrainer.name == battleScreen.opponentProfile.displayName,
      );
      expect(
        battleScreen.opponentParty.map((monster) => monster.definition.id),
        chosenTrainer.monsterIds,
      );
    },
  );

  testWidgets('手持ちが空の時は「自動で相手を決めて戦う」を押せない', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OpponentScreen(
            sampleData: sampleData,
            dexStore: DexStore(definitions: sampleData.definitions),
            onSelectTab: ({required tab}) {},
            onOpenSettings: () async {},
            battleRecorder: fakeBattleRecorder(
              calls: RecordedBattleCalls(),
              startBattleRecord: () async => null,
              recordedLevels: const {},
            ),
            pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
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
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('auto-match')))
          .onPressed,
      isNull,
    );
  });
}
