import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/opponent_screen.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/opponent/report_reason.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
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

  late List<Uri> openedUris;

  /// [pvpClient] を使う対戦相手の画面を、手持ちを 3 体入れて iPhone の画面の大きさ (モックの 390 × 844) で開く。
  Future<void> pumpOpponentScreen({
    required WidgetTester tester,
    required PvpClient pvpClient,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    openedUris = [];
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
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
            openUrl: ({required uri}) async {
              openedUris.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PvpClient signedInPvpClient({
    required RecordedPvpCalls calls,
    required Future<List<PvpOpponent>?> Function() fetchOpponents,
    required Future<void> Function() reportMonster,
    required Future<void> Function() blockUser,
  }) => fakePvpClient(
    calls: calls,
    fetchOpponents: fetchOpponents,
    extraDefinitions: null,
    battleRecord: (wins: 8, losses: 3),
    displayName: 'トレーナー 0001',
    reportMonster: reportMonster,
    blockUser: blockUser,
    updateDisplayName: ({required displayName}) async => displayName,
  );

  testWidgets('他のユーザー 3 人の手持ちと平均レベル、CPU トレーナー、戦績を出す', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    expect(find.text('8 勝 3 敗'), findsOneWidget);
    for (final text in [
      'トレーナー 1111',
      '平均 Lv. 7',
      'ばんざい',
      '平均 Lv. 12',
      'トレーナー 3333',
      '平均 Lv. 3',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('マグモン  Lv. 6'), findsOneWidget);
    expect(find.byKey(const Key('challenge-$cpuOpponentId')), findsOneWidget);
    // 見本の他のユーザーの代わりは、ログインして読めた時は出さない
    expect(find.text(sampleData.opponents.first.name), findsNothing);
    expect(calls.fetchOpponentsCount, 1);
  });

  testWidgets('戦える他のユーザーがいない時はそのことを出し、CPU トレーナーには挑める', (tester) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: RecordedPvpCalls(),
        fetchOpponents: () async => [],
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    expect(find.byKey(const Key('opponents-empty')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('challenge-$cpuOpponentId')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('相手を読めなかった時はエラーをそのまま出し、もう一度さがせる', (tester) async {
    final calls = RecordedPvpCalls();
    var shouldFail = true;
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async {
          if (shouldFail) {
            throw Exception('unavailable');
          }
          return opponents;
        },
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    expect(find.text('Exception: unavailable'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.byKey(const Key('retry-opponents')));
    await tester.pumpAndSettle();
    expect(find.text('ばんざい'), findsOneWidget);
    expect(calls.fetchOpponentsCount, 2);
  });

  testWidgets('相手のモンスターを長押しして理由を選んで通報すると、その相手が候補から消える', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    await tester.longPress(
      find.byKey(const Key('opponent-monster-uid-b-sample-noton')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ノートン を通報'), findsOneWidget);
    // 理由を選ぶまでは送れない
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('report-submit')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('report-reason-person_in_picture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(calls.reports, [
      (
        monsterOwnerUid: 'uid-b',
        monsterId: 'sample-noton',
        reason: ReportReason.personInPicture,
      ),
    ]);
    expect(find.text('ばんざい'), findsNothing);
    expect(find.text('トレーナー 1111'), findsOneWidget);
    expect(find.text('通報しました'), findsOneWidget);
  });

  testWidgets('通報を送れなかった時はシートにエラーを出して閉じず、お問い合わせを開ける', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        reportMonster: () async => throw Exception('not-found'),
        blockUser: () async {},
      ),
    );
    await tester.longPress(
      find.byKey(const Key('opponent-monster-uid-b-sample-noton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Exception: not-found'), findsOneWidget);
    expect(find.text('ノートン を通報'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-contact')));
    await tester.pumpAndSettle();
    expect(openedUris, [contactUri]);
    // 送れなかった通報の相手は候補から消さない
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.text('ばんざい'), findsOneWidget);
  });

  testWidgets('カードのメニューからブロックを確かめると、その相手が候補から消える', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    await tester.tap(find.byKey(const Key('opponent-menu-uid-a')));
    await tester.pumpAndSettle();
    // メニューには相手のモンスターごとの通報もある
    expect(find.text('マグモン を通報'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-uid-a')));
    await tester.pumpAndSettle();
    expect(find.text('トレーナー 1111 をブロック'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(calls.blockedUids, ['uid-a']);
    expect(find.text('トレーナー 1111'), findsNothing);
    expect(find.text('ブロックしました'), findsOneWidget);
  });

  testWidgets('通報 · ブロックの説明からお問い合わせを開ける', (tester) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: RecordedPvpCalls(),
        fetchOpponents: () async => opponents,
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    final helpButton = find.byKey(const Key('report-help'));
    await tester.ensureVisible(helpButton);
    await tester.pumpAndSettle();
    await tester.tap(helpButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-help-contact')));
    await tester.pumpAndSettle();
    expect(openedUris, [contactUri]);
  });

  testWidgets('ログインが無い時は見本の対戦相手を代わりに出し、通報しても送らずにこの画面から消す', (tester) async {
    final calls = RecordedPvpCalls();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedOutPvpClient(calls: calls),
    );
    final sampleOpponent = sampleData.opponents.first;
    expect(find.text(sampleOpponent.name), findsOneWidget);
    expect(find.byKey(const Key('battle-record')), findsNothing);

    await tester.longPress(
      find.byKey(
        Key(
          'opponent-monster-${sampleOpponent.id}-${sampleOpponent.monsterIds.first}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(calls.reports, isEmpty);
    expect(find.text(sampleOpponent.name), findsNothing);
  });
}
