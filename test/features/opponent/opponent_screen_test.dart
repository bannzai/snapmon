import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';
import 'package:snapmon/features/opponent/opponent_screen.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/opponent/report_reason.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
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
    // 他のユーザーが 3 人いても CPU トレーナーは 1 人出す
    for (final (index, cpuTrainer) in sampleData.cpuTrainers.indexed) {
      expect(
        find.byKey(
          Key('challenge-${cpuTrainer.opponent.id}'),
          skipOffstage: false,
        ),
        index == 0 ? findsOneWidget : findsNothing,
        reason: cpuTrainer.opponent.id,
      );
    }
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
            find.byKey(
              Key('challenge-${sampleData.cpuTrainers.first.opponent.id}'),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  for (final pvpOpponentCount in [0, 1, 2]) {
    testWidgets(
      '他のユーザーが $pvpOpponentCount 人の時は CPU トレーナーで埋めて 3 人並べ、CPU トレーナーには CPU の名前を出して通報・ブロックのメニューを出さない',
      (tester) async {
        await pumpOpponentScreen(
          tester: tester,
          pvpClient: signedInPvpClient(
            calls: RecordedPvpCalls(),
            fetchOpponents: () async =>
                opponents.take(pvpOpponentCount).toList(),
            reportMonster: () async {},
            blockUser: () async {},
          ),
        );
        for (final opponent in opponents.take(pvpOpponentCount)) {
          expect(
            find.byKey(
              Key('opponent-menu-${opponent.opponentUid}'),
              skipOffstage: false,
            ),
            findsOneWidget,
            reason: opponent.opponentUid,
          );
        }
        final cpuTrainerCount = 3 - pvpOpponentCount;
        for (final (index, cpuTrainer) in sampleData.cpuTrainers.indexed) {
          expect(
            find.byKey(
              Key('opponent-card-${cpuTrainer.opponent.id}'),
              skipOffstage: false,
            ),
            index < cpuTrainerCount ? findsOneWidget : findsNothing,
            reason: cpuTrainer.opponent.id,
          );
          if (index < cpuTrainerCount) {
            expect(
              find.text(cpuTrainer.opponent.name, skipOffstage: false),
              findsOneWidget,
            );
            expect(cpuTrainer.opponent.name, startsWith('CPU '));
            expect(
              find.byKey(
                Key('opponent-menu-${cpuTrainer.opponent.id}'),
                skipOffstage: false,
              ),
              findsNothing,
            );
          }
        }
      },
    );
  }

  testWidgets('CPU トレーナーのカードの平均レベルは、どのトレーナーも自分の手持ちの平均になる', (tester) async {
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: RecordedPvpCalls(),
        fetchOpponents: () async => [],
        reportMonster: () async {},
        blockUser: () async {},
      ),
    );
    // 他のユーザーがいない時は CPU トレーナーを 3 人並べる (手持ち 2 体のミナト・ソラと 1 体のハル)
    expect(
      find.text(
        '平均 Lv. ${averagePartyLevel(party: (DexStore(definitions: sampleData.definitions)..replaceAll(monsters: sampleData.monsters)).party)} 前後',
        skipOffstage: false,
      ),
      findsNWidgets(3),
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
    expect(find.text('トレーナー 1111 と互いに対戦の相手に出なくなります'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(calls.blockedUids, ['uid-a']);
    expect(find.text('トレーナー 1111'), findsNothing);
    expect(find.text('ブロックしました'), findsOneWidget);
  });

  testWidgets('送っている間にシートを閉じても、送れたら相手を候補から消す', (tester) async {
    final calls = RecordedPvpCalls();
    final reportCompleter = Completer<void>();
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () async => opponents,
        reportMonster: () => reportCompleter.future,
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
    await tester.pump();
    // シートの外を押して閉じる
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.text('ノートン を通報'), findsNothing);
    expect(find.text('ばんざい'), findsOneWidget);

    reportCompleter.complete();
    await tester.pumpAndSettle();
    expect(calls.reports.single.monsterOwnerUid, 'uid-b');
    expect(find.text('ばんざい'), findsNothing);
  });

  testWidgets('ブロックを送っている間に読み直しても、読み込みの結果にブロックした相手を戻さない', (tester) async {
    final calls = RecordedPvpCalls();
    final blockCompleter = Completer<void>();
    final reloadCompleter = Completer<List<PvpOpponent>>();
    var fetchCount = 0;
    await pumpOpponentScreen(
      tester: tester,
      pvpClient: signedInPvpClient(
        calls: calls,
        fetchOpponents: () => ++fetchCount == 1
            ? Future.value(opponents)
            : reloadCompleter.future,
        reportMonster: () async {},
        blockUser: () => blockCompleter.future,
      ),
    );
    await tester.tap(find.byKey(const Key('opponent-menu-uid-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-uid-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    // ブロックを送っている間に読み直す (サーバーはブロックの保存前の候補を返す)
    await tester.tap(find.byKey(const Key('reload-opponents')));
    await tester.pump();
    blockCompleter.complete();
    await tester.pumpAndSettle();
    reloadCompleter.complete(opponents);
    await tester.pumpAndSettle();
    expect(calls.blockedUids, ['uid-a']);
    expect(find.text('トレーナー 1111'), findsNothing);
    expect(find.text('ばんざい'), findsOneWidget);
  });

  testWidgets('横向きの低い画面でも通報のシートをスクロールして送れる', (tester) async {
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
    // シートを開いたまま横向きにする
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    final otherReason = find.byKey(const Key('report-reason-other'));
    await tester.ensureVisible(otherReason);
    await tester.pumpAndSettle();
    await tester.tap(otherReason);
    await tester.pumpAndSettle();
    final submitButton = find.byKey(const Key('report-submit'));
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls.reports.single.reason, ReportReason.other);
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
