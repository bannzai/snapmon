import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';
import 'package:snapmon/features/opponent/opponent_screen.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/monster_ui/monster_parts.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../game_audio_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 見本のモンスター [monsterID] を、他のユーザーの [level] のモンスターにする (元の写真の参照は返らないため持たない)。
  OwnedMonster opponentMonster({
    required String monsterID,
    required int level,
  }) {
    final sample = sampleData.monsterByID(monsterID: monsterID);
    return OwnedMonster(
      definition: sample.definition,
      level: level,
      actionCardMoveIDs: const [],
      artPath: null,
      definitionIDs: const [],
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
        opponentMonster(monsterID: 'sample-mugmon', level: 6),
        opponentMonster(monsterID: 'sample-keybon', level: 8),
      ],
    ),
    PvpOpponent(
      opponentUid: 'uid-b',
      displayName: 'ばんざい',
      iconPath: null,
      monsters: [opponentMonster(monsterID: 'sample-noton', level: 12)],
    ),
    PvpOpponent(
      opponentUid: 'uid-c',
      displayName: 'トレーナー 3333',
      iconPath: null,
      monsters: [opponentMonster(monsterID: 'sample-ringora', level: 3)],
    ),
  ];

  /// [pumpOpponentScreen] で開いた画面が流した BGM・効果音。開くたびに作り直す。
  late RecordedAudioCalls audioCalls;

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
    audioCalls = RecordedAudioCalls();
    await tester.pumpWidget(
      GameAudioScope(
        gameAudio: fakeGameAudio(
          calls: audioCalls,
          isBackgroundMusicEnabled: true,
          isSoundEffectsEnabled: true,
          waitsForUserInteractionBeforeBackgroundMusic: false,
        ),
        child: MaterialApp(
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OpponentScreen(
              sampleData: sampleData,
              dexStore: dexStore,
              onSelectScene: ({required scene}) {},
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
    'ログインしていても他のユーザーの手持ちを読まず、戦績と「ランダムな相手と戦う」だけを出し、CPU トレーナーの一覧・「ほかの相手をさがす」・通報・ブロックを出さない',
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
      // 相手の一覧は出さず、CPU トレーナーの名前も見本のモンスターの札 (自分の手持ち以外) も出ない (issue #217)
      for (final cpuTrainerName in sampleData.cpuTrainerNames) {
        expect(
          find.text(cpuTrainerName, skipOffstage: false),
          findsNothing,
          reason: cpuTrainerName,
        );
      }
      expect(
        find.byKey(const Key('random-battle'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('random-battle')))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);
      for (final text in ['相手をえらぶ', '挑む', 'ほかの相手をさがす']) {
        expect(
          find.text(text, skipOffstage: false),
          findsNothing,
          reason: text,
        );
      }
      for (final key in ['reload-opponents', 'report-help']) {
        expect(
          find.byKey(Key(key), skipOffstage: false),
          findsNothing,
          reason: key,
        );
      }
    },
  );

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

  testWidgets('ログインが無い時は戦績を出さず、見本の対戦相手を出さずに「ランダムな相手と戦う」を押せる', (tester) async {
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
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('random-battle')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('自分のアイコン (未登録は既定の印) と表示名を戦績と並べ、手持ちの札にモンスターの絵を出す', (tester) async {
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
    for (final monster in party) {
      expect(
        find.descendant(
          of: find.byKey(
            Key('party-monster-${monster.definition.id}'),
            skipOffstage: false,
          ),
          matching: find.byType(MonsterArt, skipOffstage: false),
        ),
        findsOneWidget,
        reason: monster.definition.id,
      );
    }
    expect(
      find.byType(MonsterArt, skipOffstage: false),
      findsNWidgets(party.length),
    );
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

  /// プロフィールの読み込みを [fetchProfile] に差し替えた、ログインしている時の相手の取得。
  PvpClient pvpClientWithFetchProfile({
    required Future<PlayerProfile?> Function() fetchProfile,
  }) {
    final pvpClient = signedInPvpClient(calls: RecordedPvpCalls());
    return PvpClient(
      fetchOpponents: pvpClient.fetchOpponents,
      fetchDefinitions: pvpClient.fetchDefinitions,
      reportMonster: pvpClient.reportMonster,
      blockUser: pvpClient.blockUser,
      fetchBattleRecord: pvpClient.fetchBattleRecord,
      fetchProfile: fetchProfile,
      updateDisplayName: pvpClient.updateDisplayName,
      updateIcon: pvpClient.updateIcon,
    );
  }

  testWidgets('設定を閉じた後の読み直しに失敗したら、古いプロフィールの札を消し、バトルにも渡さない', (tester) async {
    var fetchProfileFails = false;
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchProfile(
        fetchProfile: () async {
          if (fetchProfileFails) {
            throw StateError('プロフィールを読めません');
          }
          return (displayName: 'トレーナー 0001', iconPath: null);
        },
      ),
      onOpenSettings: () async => fetchProfileFails = true,
    );
    expect(
      find.byKey(const Key('opponent-tab-player-trainer')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opponent-tab-player-trainer')), findsNothing);
    expect(find.text('トレーナー 0001'), findsNothing);
    await tester.tap(find.byKey(const Key('random-battle')));
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<BattleScreen>(find.byType(BattleScreen)).playerProfile,
      isNull,
    );
  });

  testWidgets('読み直しの後に前の読み込みの結果が届いても、読み直した値を上書きしない', (tester) async {
    final fetchProfileReplies = <Completer<PlayerProfile?>>[];
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchProfile(
        fetchProfile: () {
          final reply = Completer<PlayerProfile?>();
          fetchProfileReplies.add(reply);
          return reply.future;
        },
      ),
      onOpenSettings: () async {},
    );
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    expect(fetchProfileReplies, hasLength(2));
    fetchProfileReplies[1].complete((displayName: 'ばんざい', iconPath: null));
    await tester.pump();
    fetchProfileReplies[0].complete((
      displayName: 'トレーナー 0001',
      iconPath: null,
    ));
    await tester.pump();
    expect(find.text('ばんざい'), findsOneWidget);
    expect(find.text('トレーナー 0001'), findsNothing);
  });

  testWidgets('読み直しの後に前の読み込みが失敗しても、読み直した値の札を消さない', (tester) async {
    final fetchProfileReplies = <Completer<PlayerProfile?>>[];
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchProfile(
        fetchProfile: () {
          final reply = Completer<PlayerProfile?>();
          fetchProfileReplies.add(reply);
          return reply.future;
        },
      ),
      onOpenSettings: () async {},
    );
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    fetchProfileReplies[1].complete((displayName: 'ばんざい', iconPath: null));
    await tester.pump();
    fetchProfileReplies[0].completeError(StateError('プロフィールを読めません'));
    await tester.pump();
    expect(find.text('ばんざい'), findsOneWidget);
  });

  /// 戦績の読み込みを [fetchBattleRecord] に差し替えた、ログインしている時の相手の取得。
  PvpClient pvpClientWithFetchBattleRecord({
    required Future<({int wins, int losses})?> Function() fetchBattleRecord,
  }) {
    final pvpClient = signedInPvpClient(calls: RecordedPvpCalls());
    return PvpClient(
      fetchOpponents: pvpClient.fetchOpponents,
      fetchDefinitions: pvpClient.fetchDefinitions,
      reportMonster: pvpClient.reportMonster,
      blockUser: pvpClient.blockUser,
      fetchBattleRecord: fetchBattleRecord,
      fetchProfile: pvpClient.fetchProfile,
      updateDisplayName: pvpClient.updateDisplayName,
      updateIcon: pvpClient.updateIcon,
    );
  }

  /// 「ランダムな相手と戦う」でバトルに入り、バトルの画面を閉じて対戦のシーンに戻る (閉じると戦績を読み直す)。
  Future<void> battleAndReturn({required WidgetTester tester}) async {
    await tester.tap(find.byKey(const Key('random-battle')));
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    Navigator.of(tester.element(find.byType(BattleScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    '勝敗の画面の「もう一回対戦する」で閉じると、前のバトルの画面の破棄を待ってから次のバトルの画面を開き、バトルの BGM を流す',
    (tester) async {
      await pumpOpponentScreen(
        tester: tester,
        pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
        onOpenSettings: () async {},
      );
      await tester.tap(find.byKey(const Key('random-battle')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final firstBattle = tester.widget<BattleScreen>(
        find.byType(BattleScreen),
      );
      Navigator.of(
        tester.element(find.byType(BattleScreen)),
      ).pop(BattleScreenAction.rematch);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      // 前の画面の破棄を待ってから次の画面を開くため、開いた後のフレームをもう 1 秒進める
      await tester.pump(const Duration(seconds: 1));
      final secondBattle = tester.widget<BattleScreen>(
        find.byType(BattleScreen),
      );
      expect(identical(secondBattle, firstBattle), isFalse);
      // 前の画面の破棄がホームの BGM に戻した後に次の画面がバトルの BGM を流すため、最後はバトルの BGM
      expect(
        audioCalls.playedBackgroundMusicAssetPaths.last,
        BackgroundMusic.battle.assetPath,
      );

      // 「もどる」で閉じた時は次のバトルを開かずに対戦のシーンに戻る
      Navigator.of(tester.element(find.byType(BattleScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BattleScreen), findsNothing);
      expect(find.byKey(const Key('random-battle')), findsOneWidget);
    },
  );

  testWidgets('バトルの後の戦績の読み直しに失敗したら、古い勝敗を出さずにエラーを出す', (tester) async {
    var fetchBattleRecordFails = false;
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchBattleRecord(
        fetchBattleRecord: () async {
          if (fetchBattleRecordFails) {
            throw StateError('戦績を読めません');
          }
          return (wins: 8, losses: 3);
        },
      ),
      onOpenSettings: () async {},
    );
    expect(find.text('8 勝 3 敗'), findsOneWidget);
    fetchBattleRecordFails = true;
    await battleAndReturn(tester: tester);
    expect(find.byType(BattleScreen), findsNothing);
    expect(find.text('8 勝 3 敗'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('battle-record'))).data,
      StateError('戦績を読めません').toString(),
    );
  });

  testWidgets('バトルの後の読み直しの後に前の読み込みの結果が届いても、読み直した戦績を上書きしない', (tester) async {
    final fetchBattleRecordReplies = <Completer<({int wins, int losses})?>>[];
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchBattleRecord(
        fetchBattleRecord: () {
          final reply = Completer<({int wins, int losses})?>();
          fetchBattleRecordReplies.add(reply);
          return reply.future;
        },
      ),
      onOpenSettings: () async {},
    );
    await battleAndReturn(tester: tester);
    expect(fetchBattleRecordReplies, hasLength(2));
    fetchBattleRecordReplies[1].complete((wins: 9, losses: 3));
    await tester.pump();
    fetchBattleRecordReplies[0].complete((wins: 8, losses: 3));
    await tester.pump();
    expect(find.text('9 勝 3 敗'), findsOneWidget);
    expect(find.text('8 勝 3 敗'), findsNothing);
  });

  testWidgets('バトルの後の読み直しの後に前の読み込みが失敗しても、読み直した戦績を消さない', (tester) async {
    final fetchBattleRecordReplies = <Completer<({int wins, int losses})?>>[];
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: pvpClientWithFetchBattleRecord(
        fetchBattleRecord: () {
          final reply = Completer<({int wins, int losses})?>();
          fetchBattleRecordReplies.add(reply);
          return reply.future;
        },
      ),
      onOpenSettings: () async {},
    );
    await battleAndReturn(tester: tester);
    expect(fetchBattleRecordReplies, hasLength(2));
    fetchBattleRecordReplies[1].complete((wins: 9, losses: 3));
    await tester.pump();
    fetchBattleRecordReplies[0].completeError(StateError('戦績を読めません'));
    await tester.pump();
    expect(find.text('9 勝 3 敗'), findsOneWidget);
  });

  testWidgets(
    '「ランダムな相手と戦う」は、CPU トレーナーの名前と、自分の手持ちと同じ数で同じ絵を含まない自分の平均レベルの見本のモンスターを相手にしてバトルに入り、自分と相手の名前を渡す',
    (tester) async {
      await pumpOpponentScreen(
        tester: tester,
        pvpClient: signedInPvpClient(calls: RecordedPvpCalls()),
        onOpenSettings: () async {},
      );
      await tester.tap(find.byKey(const Key('random-battle')));
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
      expect(battleScreen.opponentKind, BattleOpponentKind.cpu);
      expect(
        sampleData.cpuTrainerNames,
        contains(battleScreen.opponentDisplayName),
      );
      // 相手の手持ちは乱数で組む (lib/features/opponent/cpu_party.dart の chooseRandomCpuOpponent)
      final party = (DexStore(
        definitions: sampleData.definitions,
      )..replaceAll(monsters: sampleData.monsters)).party;
      final partyArtPaths = {for (final monster in party) monster.artPath};
      expect(battleScreen.opponentParty, hasLength(party.length));
      for (final monster in battleScreen.opponentParty) {
        expect(partyArtPaths.contains(monster.artPath), isFalse);
        expect(monster.level, averagePartyLevel(party: party));
      }
    },
  );

  testWidgets('手持ちが空の時は「ランダムな相手と戦う」を押せない', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GameAudioScope(
        gameAudio: fakeGameAudio(
          calls: RecordedAudioCalls(),
          isBackgroundMusicEnabled: true,
          isSoundEffectsEnabled: true,
          waitsForUserInteractionBeforeBackgroundMusic: false,
        ),
        child: MaterialApp(
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OpponentScreen(
              sampleData: sampleData,
              dexStore: DexStore(definitions: sampleData.definitions),
              onSelectScene: ({required scene}) {},
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
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('random-battle')))
          .onPressed,
      isNull,
    );
  });
}
