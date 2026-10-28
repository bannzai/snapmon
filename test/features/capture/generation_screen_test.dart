import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/generation_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../monster_generator_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  late DexStore dexStore;
  late RecordedGenerationCalls calls;
  late RecordedBattleCalls battleCalls;

  /// [generator] の生成の画面を、閉じた時の [ResultScreenAction] を [closedActions] に残す画面から開く。
  /// [startsFirstBattle] が true なら初回の導線 (生まれたらそのまま戦う) にする。初回の導線は相手を探す表示が止まらないため、
  /// 開いた後は pumpAndSettle ではなく時間を指定して進める。[sourcePhoto]・[photoSource]・[cropsWhenSubjectNotFound] は
  /// 生成の画面にそのまま渡す (範囲を決める画面を確かめるテストだけが、画像として読める写真を渡す)。
  Future<List<ResultScreenAction?>> pumpGenerationScreen({
    required WidgetTester tester,
    required MonsterGenerator generator,
    required bool startsFirstBattle,
    Uint8List? sourcePhoto,
    GenerationPhotoSource photoSource = GenerationPhotoSource.album,
    bool cropsWhenSubjectNotFound = true,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final closedActions = <ResultScreenAction?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => closedActions.add(
                  await Navigator.of(context).push(
                    MaterialPageRoute<ResultScreenAction>(
                      builder: (context) => GenerationScreen(
                        sourcePhoto: sourcePhoto ?? testPhotoBytes,
                        photoSource: photoSource,
                        cropsWhenSubjectNotFound: cropsWhenSubjectNotFound,
                        monsterGenerator: generator,
                        dexStore: dexStore,
                        cardSharer: fakeCardSharer(
                          calls: RecordedShareCalls(),
                          artImage: null,
                          shareResultStatus: ShareResultStatus.success,
                        ),
                        startsFirstBattle: startsFirstBattle,
                        sampleData: sampleData,
                        pvpClient: signedOutPvpClient(
                          calls: RecordedPvpCalls(),
                        ),
                        battleRecorder: fakeBattleRecorder(
                          calls: battleCalls,
                          startBattleRecord: () async => null,
                          recordedLevels: const {},
                        ),
                        openUrl: ({required uri}) async => true,
                      ),
                    ),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    if (startsFirstBattle) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    } else {
      await tester.pumpAndSettle();
    }
    return closedActions;
  }

  /// 計測の `first_experience` の `step` (送った順)。
  List<Object?> firstExperienceSteps() => [
    for (final logged in [...calls.loggedEvents, ...battleCalls.loggedEvents])
      if (logged.event == AnalyticsEvent.firstExperience)
        logged.parameters?['step'],
  ];

  /// サーバーが [monsterId] のモンスターを保存して図鑑に届けた後に、[result] を返す生成。
  Future<GenerationResult> Function({required String requestId})
  savedGeneration({
    required String monsterId,
    required GenerationStatus status,
    required String? resultRequestId,
  }) => ({required requestId}) async {
    dexStore.applyServerSnapshot(
      monsters: [generatedWaxMonster(monsterId: monsterId)],
      partyMonsterIds: null,
      definitions: definitionsWithWax(base: sampleData.definitions),
    );
    return GenerationResult(
      requestId: resultRequestId ?? requestId,
      status: status,
      monsterId: monsterId,
      rejectionReason: null,
    );
  };

  Future<GenerationResult> unexpectedFetch({required String requestId}) =>
      throw StateError('fetchGeneration は呼ばない');

  setUp(() {
    dexStore = DexStore(definitions: sampleData.definitions);
    calls = RecordedGenerationCalls();
    battleCalls = RecordedBattleCalls();
  });

  testWidgets('新しく保存された時は生まれた画面を開き、生成完了のイベントを 1 回送る', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.saved,
          resultRequestId: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('あたらしい なかま'), findsOneWidget);
    // 属性と最初の技は図鑑の定義 (その場で作った定義) にだけあり、見本の定義では引けない
    expect(find.text('ろう'), findsOneWidget);
    expect(find.text('ろうアタック PP 30'), findsOneWidget);
    expect(calls.uploadedRequestIds, ['request-1']);
    expect(calls.requestedRequestIds, ['request-1']);
    expect(calls.loggedEvents, hasLength(1));
    expect(calls.loggedEvents.single.event, AnalyticsEvent.monsterGenerated);
    expect(calls.loggedEvents.single.parameters, {'source': 'album'});
  });

  group('被写体の範囲', () {
    /// 幅 40・高さ 30 の画像として読める写真 (範囲を決める画面は写真の大きさを読むため)。
    final readablePhoto = Uint8List.fromList(
      img.encodePng(img.Image(width: 40, height: 30)),
    );

    MonsterGenerator generatorWithSubjectMask({
      required Future<Uint8List?> Function({required Uint8List photo})
      createSubjectMask,
    }) => fakeMonsterGenerator(
      calls: calls,
      albumPhoto: null,
      uploadError: null,
      createSubjectMask: createSubjectMask,
      requestGeneration: savedGeneration(
        monsterId: 'm1',
        status: GenerationStatus.saved,
        resultRequestId: null,
      ),
      fetchGeneration: unexpectedFetch,
    );

    testWidgets('OS の切り出しが被写体を見つけたら、そのマスクを置いて ios_subject で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
        ),
      );
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(calls.uploadedMasks, [
        (requestId: 'request-1', mask: testSubjectMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.iosSubject]);
    });

    testWidgets('OS の切り出しが被写体を見つけない時は範囲を決める画面を出し、決めた枠をマスクにして crop で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        sourcePhoto: readablePhoto,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => null,
        ),
      );
      expect(find.text('モンスターにする範囲'), findsOneWidget);
      expect(find.textContaining('自動の切り出しを使えませんでした'), findsNothing);
      expect(calls.uploadedRequestIds, isEmpty);

      // 枠 (初めは中央の 30 × 30) を左へ動かすと、写真の左端で止まる
      await tester.drag(
        find.byKey(const Key('square-crop-area')),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(calls.squareMaskCrops, [(left: 0.0, top: 0.0, side: 30.0)]);
      expect(calls.uploadedMasks, [
        (requestId: 'request-1', mask: testSquareMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.crop]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('crop のマスクを作れずにもう一度試す時は、OS の切り出しをやり直さず決めた枠のまま範囲を決める画面に戻す', (
      tester,
    ) async {
      var subjectMaskCount = 0;
      var squareMaskCount = 0;
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        sourcePhoto: readablePhoto,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async {
            subjectMaskCount++;
            return null;
          },
          createSquareMask: ({required photo, required crop}) async {
            if (++squareMaskCount == 1) {
              throw const FormatException('マスクを作れません');
            }
            return testSquareMaskBytes;
          },
          requestGeneration: savedGeneration(
            monsterId: 'm1',
            status: GenerationStatus.saved,
            resultRequestId: null,
          ),
          fetchGeneration: unexpectedFetch,
        ),
      );
      await tester.drag(
        find.byKey(const Key('square-crop-area')),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(find.textContaining('マスクを作れません'), findsOneWidget);
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(find.text('モンスターにする範囲'), findsOneWidget);
      expect(subjectMaskCount, 1);
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(calls.squareMaskCrops, [
        (left: 0.0, top: 0.0, side: 30.0),
        (left: 0.0, top: 0.0, side: 30.0),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.crop]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('OS の切り出しが失敗した時は、そのエラーを出して範囲を決める画面にする', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        sourcePhoto: readablePhoto,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async =>
              throw PlatformException(
                code: 'subject_mask_failed',
                message: 'Vision のエラー',
              ),
        ),
      );
      expect(find.text('モンスターにする範囲'), findsOneWidget);
      expect(find.textContaining('Vision のエラー'), findsOneWidget);
    });

    testWidgets('範囲を決めない設定 (開発者メニューの見本の写真) で被写体が無い時は、マスクを置かずに none で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        photoSource: GenerationPhotoSource.sample,
        cropsWhenSubjectNotFound: false,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => null,
        ),
      );
      expect(find.text('モンスターにする範囲'), findsNothing);
      expect(calls.uploadedMasks, isEmpty);
      expect(calls.requestedMaskSources, [GenerationMaskSource.none]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('写真が見つからず置き直す時は、マスクも置き直し、範囲は決め直させない', (tester) async {
      var requestCount = 0;
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        sourcePhoto: readablePhoto,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async => null,
          requestGeneration: ({required requestId}) async {
            if (++requestCount == 1) {
              throw const GenerationPhotoMissingException(
                message: '写真が見つかりません',
              );
            }
            return savedGeneration(
              monsterId: 'm1',
              status: GenerationStatus.saved,
              resultRequestId: null,
            )(requestId: requestId);
          },
          fetchGeneration: unexpectedFetch,
        ),
      );
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(find.text('写真が見つかりません'), findsOneWidget);
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(find.text('モンスターにする範囲'), findsNothing);
      expect(calls.squareMaskCrops, hasLength(1));
      expect(calls.uploadedRequestIds, ['request-1', 'request-1']);
      expect(calls.uploadedMasks, hasLength(2));
      expect(calls.requestedMaskSources, [
        GenerationMaskSource.crop,
        GenerationMaskSource.crop,
      ]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });
  });

  testWidgets('同じ写真の別の要求の結果を使い回した時は、図鑑にいるモンスターを開きイベントを送らない', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.saved,
          resultRequestId: 'earlier-request',
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('もう図鑑にいます'), findsOneWidget);
    expect(find.text('ロウソクン'), findsOneWidget);
    expect(calls.loggedEvents, isEmpty);
  });

  testWidgets('同じ被写体 (duplicate) の時は、二重に登録せず図鑑にいるモンスターを開く', (tester) async {
    final closedActions = await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.duplicate,
          resultRequestId: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('もう図鑑にいます'), findsOneWidget);
    expect(dexStore.monsters, hasLength(1));
    expect(calls.loggedEvents, isEmpty);

    // 「もう 1 体撮る」で生まれた画面と生成の画面を閉じ、撮る画面に戻る
    await tester.tap(find.text('もう 1 体撮る'));
    await tester.pumpAndSettle();
    expect(find.text('開く'), findsOneWidget);
    expect(closedActions, [null]);
  });

  testWidgets('判定待ちの時はもう少し待ってねを出し、同じ要求 ID で読み直して生まれたら生まれた画面を開く', (
    tester,
  ) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async => GenerationResult(
          requestId: requestId,
          status: GenerationStatus.pendingJudge,
          monsterId: null,
          rejectionReason: null,
        ),
        fetchGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.saved,
          resultRequestId: null,
        ),
      ),
    );
    expect(find.text('もう少し待ってね'), findsOneWidget);
    await tester.tap(find.text('もう一度確かめる'));
    await tester.pumpAndSettle();
    expect(calls.fetchedRequestIds, ['request-1']);
    expect(find.text('あたらしい なかま'), findsOneWidget);
    expect(calls.loggedEvents, hasLength(1));
  });

  testWidgets('使い回した別の要求が判定待ちの時は、使い回し先の要求 ID で読み直す', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async =>
            const GenerationResult(
              requestId: 'earlier-request',
              status: GenerationStatus.pendingJudge,
              monsterId: null,
              rejectionReason: null,
            ),
        fetchGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.saved,
          resultRequestId: null,
        ),
      ),
    );
    await tester.tap(find.text('もう一度確かめる'));
    await tester.pumpAndSettle();
    expect(calls.fetchedRequestIds, ['earlier-request']);
    // 読み直した結果は使い回し先の要求のもので、この写真から新しく生まれたのではない
    expect(find.text('もう図鑑にいます'), findsOneWidget);
    expect(calls.loggedEvents, isEmpty);
  });

  testWidgets('生成しなかった時は理由を出す', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async => GenerationResult(
          requestId: requestId,
          status: GenerationStatus.rejected,
          monsterId: null,
          rejectionReason: GenerationRejectionReason.faceDetected,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('生まれませんでした'), findsOneWidget);
    expect(find.text('人が写っている写真からは作れません\n物だけを撮ってください'), findsOneWidget);
    expect(calls.loggedEvents, isEmpty);
  });

  testWidgets('失敗した時は失敗を出す', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async => GenerationResult(
          requestId: requestId,
          status: GenerationStatus.failed,
          monsterId: null,
          rejectionReason: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('生成に失敗しました\nもう一度撮ってみてください'), findsOneWidget);
  });

  testWidgets('呼び出しが例外で終わったらエラーをそのまま出し、もう一度試すと写真を送り直さず同じ要求 ID で呼ぶ', (
    tester,
  ) async {
    var remainingFailureCount = 1;
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async {
          if (remainingFailureCount > 0) {
            remainingFailureCount--;
            throw Exception('deadline-exceeded');
          }
          return savedGeneration(
            monsterId: 'm1',
            status: GenerationStatus.saved,
            resultRequestId: null,
          )(requestId: requestId);
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('Exception: deadline-exceeded'), findsOneWidget);
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(calls.uploadedRequestIds, ['request-1']);
    expect(calls.requestedRequestIds, ['request-1', 'request-1']);
    expect(find.text('あたらしい なかま'), findsOneWidget);
  });

  testWidgets('サーバーが写真を見つけられなかった時は、もう一度試すと同じ要求 ID で写真を置き直して呼ぶ', (tester) async {
    var remainingFailureCount = 1;
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestId}) async {
          if (remainingFailureCount > 0) {
            remainingFailureCount--;
            throw const GenerationPhotoMissingException(
              message: '写真が見つかりません。写真を上げ直してください',
            );
          }
          return savedGeneration(
            monsterId: 'm1',
            status: GenerationStatus.saved,
            resultRequestId: null,
          )(requestId: requestId);
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('写真が見つかりません。写真を上げ直してください'), findsOneWidget);
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(calls.uploadedRequestIds, ['request-1', 'request-1']);
    expect(calls.requestedRequestIds, ['request-1', 'request-1']);
    expect(find.text('あたらしい なかま'), findsOneWidget);
  });

  testWidgets('ログインしていない時 (DEBUG でログインを飛ばした) は送る前のエラーをそのまま出し、生成を呼ばない', (
    tester,
  ) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: StateError('ログインしていないため生成できません'),
        requestGeneration: ({required requestId}) =>
            throw StateError('requestGeneration は呼ばない'),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('Bad state: ログインしていないため生成できません'), findsOneWidget);
    expect(find.text('もう一度試す'), findsOneWidget);
    expect(calls.requestedRequestIds, isEmpty);
  });

  testWidgets('生まれた画面で手持ちに入れると、図鑑を開くよう閉じる', (tester) async {
    final closedActions = await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: savedGeneration(
          monsterId: 'm1',
          status: GenerationStatus.saved,
          resultRequestId: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    await tester.tap(find.text('手持ちに入れる'));
    await tester.pumpAndSettle();
    expect(closedActions, [ResultScreenAction.openDex]);
    expect(dexStore.isInParty(monsterId: 'm1'), isTrue);
  });

  group('初回の導線 (手持ちが空の時)', () {
    /// 生成の結果の表示まで進める (相手を探す表示の進捗は止まらないため、時間を指定して進める)。
    Future<void> pumpUntilResult({required WidgetTester tester}) async {
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('生成しなかった時 (rejected) は相手を探す表示をやめ、初回でない時と同じ理由を出す', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: ({required requestId}) async => GenerationResult(
            requestId: requestId,
            status: GenerationStatus.rejected,
            monsterId: null,
            rejectionReason: GenerationRejectionReason.explicitContent,
          ),
          fetchGeneration: unexpectedFetch,
        ),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('相手を探しています'), findsNothing);
      expect(find.text('生まれませんでした'), findsOneWidget);
      expect(find.text('この写真からはモンスターを作れません'), findsOneWidget);
      expect(find.byType(BattleScreen), findsNothing);
      expect(dexStore.party, isEmpty);
      expect(firstExperienceSteps(), ['photo_selected', 'generation_failed']);
    });

    testWidgets('判定待ち (pending_judge) の時は「もう少し待ってね」に戻す', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: ({required requestId}) async => GenerationResult(
            requestId: requestId,
            status: GenerationStatus.pendingJudge,
            monsterId: null,
            rejectionReason: null,
          ),
          fetchGeneration: unexpectedFetch,
        ),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('相手を探しています'), findsNothing);
      expect(find.text('もう少し待ってね'), findsOneWidget);
      expect(find.text('もう一度確かめる'), findsOneWidget);
      expect(find.byType(BattleScreen), findsNothing);
      expect(firstExperienceSteps(), ['photo_selected', 'generation_failed']);
    });

    testWidgets('呼び出しが例外で終わった時はエラーを出し、generation_failed を送る', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: ({required requestId}) async =>
              throw Exception('deadline-exceeded'),
          fetchGeneration: unexpectedFetch,
        ),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('生成できませんでした'), findsOneWidget);
      expect(find.text('Exception: deadline-exceeded'), findsOneWidget);
      expect(firstExperienceSteps(), ['photo_selected', 'generation_failed']);
    });

    testWidgets(
      '同じ被写体 (duplicate) の時は「もう図鑑にいます」を出し、「このモンスターで戦う」でそのモンスターを手持ちに入れてバトルに進む',
      (tester) async {
        await pumpGenerationScreen(
          tester: tester,
          startsFirstBattle: true,
          generator: fakeMonsterGenerator(
            calls: calls,
            albumPhoto: null,
            uploadError: null,
            requestGeneration: savedGeneration(
              monsterId: 'm1',
              status: GenerationStatus.duplicate,
              resultRequestId: null,
            ),
            fetchGeneration: unexpectedFetch,
          ),
        );
        await pumpUntilResult(tester: tester);
        expect(find.text('相手を探しています'), findsNothing);
        expect(find.text('もう図鑑にいます'), findsOneWidget);
        expect(
          find.text('この被写体は ロウソクン として図鑑にいます\nこのモンスターで戦えます'),
          findsOneWidget,
        );
        expect(dexStore.monsters, hasLength(1));
        // 新しく生まれていないため、生成完了のイベントは送らない
        expect(
          calls.loggedEvents.map((logged) => logged.event),
          isNot(contains(AnalyticsEvent.monsterGenerated)),
        );
        expect(firstExperienceSteps(), ['photo_selected', 'generation_failed']);

        await tester.tap(find.text('このモンスターで戦う'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(dexStore.isInParty(monsterId: 'm1'), isTrue);
        // ログインが無い時の PvP の候補は null のため、CPU トレーナーが相手になる
        expect(
          find.text(
            '${sampleData.opponents.firstWhere((opponent) => opponent.id == cpuOpponentId).name} があらわれた',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsOneWidget);
        expect(find.byKey(const Key('first-battle-hint')), findsOneWidget);
        expect(firstExperienceSteps(), [
          'photo_selected',
          'generation_failed',
          'matchmaking',
          'battle_started',
        ]);
      },
    );

    testWidgets('判定待ちから「もう一度確かめる」で生まれた時は、手持ちに入れてバトルに進む', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: ({required requestId}) async => GenerationResult(
            requestId: requestId,
            status: GenerationStatus.pendingJudge,
            monsterId: null,
            rejectionReason: null,
          ),
          fetchGeneration: savedGeneration(
            monsterId: 'm1',
            status: GenerationStatus.saved,
            resultRequestId: null,
          ),
        ),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('もう少し待ってね'), findsOneWidget);

      await tester.tap(find.text('もう一度確かめる'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.fetchedRequestIds, ['request-1']);
      expect(dexStore.isInParty(monsterId: 'm1'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BattleScreen), findsOneWidget);
      expect(firstExperienceSteps(), [
        'photo_selected',
        'generation_failed',
        'matchmaking',
        'battle_started',
      ]);
    });

    testWidgets('生成を待つ間に手持ちが届いて空でなくなった時は、バトルに進まず生まれた画面を開く', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          // Firestore の手持ち (前の端末で入れた m0) が、生成の結果より先に届く
          requestGeneration: ({required requestId}) async {
            dexStore.applyServerSnapshot(
              monsters: [
                generatedWaxMonster(monsterId: 'm0'),
                generatedWaxMonster(monsterId: 'm1'),
              ],
              partyMonsterIds: ['m0'],
              definitions: definitionsWithWax(base: sampleData.definitions),
            );
            return GenerationResult(
              requestId: requestId,
              status: GenerationStatus.saved,
              monsterId: 'm1',
              rejectionReason: null,
            );
          },
          fetchGeneration: unexpectedFetch,
        ),
      );
      await pumpUntilResult(tester: tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.byType(BattleScreen), findsNothing);
      expect(dexStore.isInParty(monsterId: 'm1'), isFalse);
      expect(firstExperienceSteps(), isNot(contains('matchmaking')));
    });
  });
}
