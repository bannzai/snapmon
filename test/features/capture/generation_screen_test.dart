import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/generation_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../game_audio_fixture.dart';
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
  /// 開いた後は pumpAndSettle ではなく時間を指定して進める。[sourcePhoto]・[photoSource]・[letsUserChooseSubjectRange] は
  /// 生成の画面にそのまま渡す (範囲を決める画面を確かめるテストだけが、画像として読める写真を渡す)。
  /// [letsUserChooseSubjectRange] の既定は false (切り抜くか・範囲を選ぶ操作を挟まずに生成まで通す)。選ぶ画面は「被写体の範囲」の
  /// テストが true を渡して確かめる。
  /// [pvpClient] が null ならログインが無い時の [PvpClient] を渡す (プロフィールを確かめるテストだけが渡す)。
  /// [settlesAfterOpening] が false なら、開いた直後で止める (人が写っている注意のダイアログや、途中の状態の結果を取り直している間の
  /// 表示を確かめるテストが渡す。裏の生成中の表示が動き続けて settle しない・settle を待つと取り直しの 40 秒が過ぎるため)。
  Future<List<ResultScreenAction?>> pumpGenerationScreen({
    required WidgetTester tester,
    required MonsterGenerator generator,
    required bool startsFirstBattle,
    bool settlesAfterOpening = true,
    PvpClient? pvpClient,
    Uint8List? sourcePhoto,
    GenerationPhotoSource photoSource = GenerationPhotoSource.album,
    bool letsUserChooseSubjectRange = false,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final closedActions = <ResultScreenAction?>[];
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
                          letsUserChooseSubjectRange:
                              letsUserChooseSubjectRange,
                          monsterGenerator: generator,
                          dexStore: dexStore,
                          cardSharer: fakeCardSharer(
                            calls: RecordedShareCalls(),
                            artImage: null,
                            shareResultStatus: ShareResultStatus.success,
                          ),
                          startsFirstBattle: startsFirstBattle,
                          sampleData: sampleData,
                          pvpClient:
                              pvpClient ??
                              signedOutPvpClient(calls: RecordedPvpCalls()),
                          battleRecorder: fakeBattleRecorder(
                            calls: battleCalls,
                            startBattleRecord: () async => null,
                            recordedLevels: const {},
                          ),
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
      ),
    );
    await tester.tap(find.text('開く'));
    if (startsFirstBattle || !settlesAfterOpening) {
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

  /// サーバーが [monsterID] のモンスターを保存して図鑑に届けた後に、[result] を返す生成。
  Future<GenerationResult> Function({required String requestID})
  savedGeneration({
    required String monsterID,
    required GenerationStatus status,
    required String? resultRequestID,
  }) => ({required requestID}) async {
    dexStore.applyServerSnapshot(
      monsters: [generatedWaxMonster(monsterID: monsterID)],
      partyMonsterIDs: null,
      definitions: definitionsWithWax(base: sampleData.definitions),
    );
    return GenerationResult(
      requestID: resultRequestID ?? requestID,
      status: status,
      monsterID: monsterID,
      rejectionReason: null,
      personDetected: false,
    );
  };

  Future<GenerationResult> unexpectedFetch({required String requestID}) =>
      throw StateError('fetchGeneration は呼ばない');

  /// サーバーが判定を待っている (途中の状態の) 生成。
  Future<GenerationResult> pendingGeneration({
    required String requestID,
  }) async => GenerationResult(
    requestID: requestID,
    status: GenerationStatus.pendingJudge,
    monsterID: null,
    rejectionReason: null,
    personDetected: false,
  );

  /// サーバーが段階をやり直している (途中の状態の) 生成。
  Future<GenerationResult> processingGeneration({
    required String requestID,
  }) async => GenerationResult(
    requestID: requestID,
    status: GenerationStatus.processing,
    monsterID: null,
    rejectionReason: null,
    personDetected: false,
  );

  /// 呼ばれるたびに [fetches] を順に呼び、使い切った後は最後のものを呼び続ける読み直し。
  Future<GenerationResult> Function({required String requestID})
  fetchesInOrder({
    required List<
      Future<GenerationResult> Function({required String requestID})
    >
    fetches,
  }) {
    var fetchCount = 0;
    return ({required requestID}) =>
        fetches[(fetchCount++).clamp(0, fetches.length - 1)](
          requestID: requestID,
        );
  }

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
          monsterID: 'm1',
          status: GenerationStatus.saved,
          resultRequestID: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('あたらしい なかま'), findsOneWidget);
    // 属性と最初の技は図鑑の定義 (その場で作った定義) にだけあり、見本の定義では引けない
    // ろう はモンスターの属性の札と、ろうアタックの属性の札の 2 つ
    expect(find.text('ろう'), findsNWidgets(2));
    expect(find.text('ろうアタック'), findsOneWidget);
    expect(calls.uploadedRequestIDs, ['request-1']);
    expect(calls.requestedRequestIDs, ['request-1']);
    expect(calls.loggedEvents, hasLength(1));
    expect(calls.loggedEvents.single.event, AnalyticsEvent.monsterGenerated);
    expect(calls.loggedEvents.single.parameters, {'source': 'album'});
  });

  testWidgets('人が写っている写真から生まれた時は、注意を出してから生まれた画面を開く', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      settlesAfterOpening: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestID}) async {
          dexStore.applyServerSnapshot(
            monsters: [generatedWaxMonster(monsterID: 'm1')],
            partyMonsterIDs: null,
            definitions: definitionsWithWax(base: sampleData.definitions),
          );
          return GenerationResult(
            requestID: requestID,
            status: GenerationStatus.saved,
            monsterID: 'm1',
            rejectionReason: null,
            personDetected: true,
          );
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('人が写っています'), findsOneWidget);
    expect(
      find.text('モンスターの画像は対戦で他の人にも見えます\n自分以外の人が写っている時は\nその人の同意を得てから使ってください'),
      findsOneWidget,
    );
    expect(find.text('あたらしい なかま'), findsNothing);
    await tester.tap(find.byKey(const Key('person-notice-close')));
    await tester.pumpAndSettle();
    expect(find.text('人が写っています'), findsNothing);
    expect(find.text('あたらしい なかま'), findsOneWidget);
    expect(calls.loggedEvents, hasLength(1));
  });

  testWidgets('同じ被写体 (duplicate) で終わった時は、人が写っていても注意を出さない', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestID}) async {
          dexStore.applyServerSnapshot(
            monsters: [generatedWaxMonster(monsterID: 'm1')],
            partyMonsterIDs: null,
            definitions: definitionsWithWax(base: sampleData.definitions),
          );
          return GenerationResult(
            requestID: requestID,
            status: GenerationStatus.duplicate,
            monsterID: 'm1',
            rejectionReason: null,
            personDetected: true,
          );
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('人が写っています'), findsNothing);
    expect(find.text('もう図鑑にいます'), findsOneWidget);
  });

  testWidgets('人が写っていない写真から生まれた時は注意を出さない', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: savedGeneration(
          monsterID: 'm1',
          status: GenerationStatus.saved,
          resultRequestID: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('人が写っています'), findsNothing);
    expect(find.text('あたらしい なかま'), findsOneWidget);
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
        monsterID: 'm1',
        status: GenerationStatus.saved,
        resultRequestID: null,
      ),
      fetchGeneration: unexpectedFetch,
    );

    testWidgets('OS の切り出しが被写体を見つけても自動では送らず、切り抜いた絵と元の写真を並べて選んでもらう', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
        ),
      );
      expect(find.text('被写体を切り抜きました'), findsOneWidget);
      expect(find.byKey(const Key('cutout-choice-cutout')), findsOneWidget);
      expect(find.byKey(const Key('cutout-choice-photo')), findsOneWidget);
      expect(find.text('切り抜いた絵で作る'), findsOneWidget);
      expect(find.text('範囲を自分で決める'), findsOneWidget);
      expect(calls.uploadedRequestIDs, isEmpty);
      expect(calls.uploadedMasks, isEmpty);
      expect(calls.requestedMaskSources, isEmpty);
    });

    testWidgets('切り抜いた絵を選ぶと、OS の切り出しのマスクを置いて ios_subject で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
        ),
      );
      await tester.tap(find.text('切り抜いた絵で作る'));
      await tester.pumpAndSettle();
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(calls.uploadedMasks, [
        (requestID: 'request-1', mask: testSubjectMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.iosSubject]);
    });

    testWidgets('範囲を自分で決めると選ぶと、範囲を決める画面を出し、OS の切り出しのマスクではなく決めた枠を crop で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        sourcePhoto: readablePhoto,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
        ),
      );
      await tester.tap(find.text('範囲を自分で決める'));
      await tester.pumpAndSettle();
      expect(find.text('モンスターにする範囲'), findsOneWidget);
      expect(find.textContaining('自動の切り出しを使えませんでした'), findsNothing);
      expect(calls.uploadedRequestIDs, isEmpty);
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(calls.squareMaskCrops, [(left: 5.0, top: 0.0, side: 30.0)]);
      expect(calls.uploadedMasks, [
        (requestID: 'request-1', mask: testSquareMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.crop]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('切り抜いた絵を選んだ後の失敗からもう一度試す時は、選ぶ画面に戻さず同じマスクで送り直す', (tester) async {
      var requestCount = 0;
      var subjectMaskCount = 0;
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async {
            subjectMaskCount++;
            return testSubjectMaskBytes;
          },
          requestGeneration: ({required requestID}) async {
            if (++requestCount == 1) {
              throw const GenerationPhotoMissingException(
                message: '写真が見つかりません',
              );
            }
            return savedGeneration(
              monsterID: 'm1',
              status: GenerationStatus.saved,
              resultRequestID: null,
            )(requestID: requestID);
          },
          fetchGeneration: unexpectedFetch,
        ),
      );
      await tester.tap(find.text('切り抜いた絵で作る'));
      await tester.pumpAndSettle();
      expect(find.text('写真が見つかりません'), findsOneWidget);
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(find.text('被写体を切り抜きました'), findsNothing);
      expect(subjectMaskCount, 1);
      expect(calls.uploadedMasks, [
        (requestID: 'request-1', mask: testSubjectMaskBytes),
        (requestID: 'request-1', mask: testSubjectMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [
        GenerationMaskSource.iosSubject,
        GenerationMaskSource.iosSubject,
      ]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('初回の導線でも、切り抜くかを選ぶまでは相手を探さず、切り抜いた絵を選ぶと相手を探す表示に進む', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        letsUserChooseSubjectRange: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
          // 生成を待っている間の表示を確かめるため、終わらせない (初回のバトルのタイマーを残さないため)
          requestGeneration: ({required requestID}) =>
              Completer<GenerationResult>().future,
          fetchGeneration: unexpectedFetch,
        ),
      );
      expect(find.text('被写体を切り抜きました'), findsOneWidget);
      expect(find.text('相手を探しています'), findsNothing);
      expect(calls.requestedMaskSources, isEmpty);
      await tester.tap(find.text('切り抜いた絵で作る'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('被写体を切り抜きました'), findsNothing);
      expect(find.text('相手を探しています'), findsOneWidget);
      expect(calls.requestedMaskSources, [GenerationMaskSource.iosSubject]);
    });

    testWidgets(
      '範囲を決めない設定 (開発者メニューの見本の写真) で被写体が見つかった時は、選ばずに ios_subject で生成する',
      (tester) async {
        await pumpGenerationScreen(
          tester: tester,
          startsFirstBattle: false,
          photoSource: GenerationPhotoSource.sample,
          generator: generatorWithSubjectMask(
            createSubjectMask: ({required photo}) async => testSubjectMaskBytes,
          ),
        );
        expect(find.text('被写体を切り抜きました'), findsNothing);
        expect(calls.uploadedMasks, [
          (requestID: 'request-1', mask: testSubjectMaskBytes),
        ]);
        expect(calls.requestedMaskSources, [GenerationMaskSource.iosSubject]);
        expect(find.text('あたらしい なかま'), findsOneWidget);
      },
    );

    testWidgets('OS の切り出しが被写体を見つけない時は範囲を決める画面を出し、決めた枠をマスクにして crop で生成する', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        sourcePhoto: readablePhoto,
        generator: generatorWithSubjectMask(
          createSubjectMask: ({required photo}) async => null,
        ),
      );
      expect(find.text('モンスターにする範囲'), findsOneWidget);
      expect(find.textContaining('自動の切り出しを使えませんでした'), findsNothing);
      expect(calls.uploadedRequestIDs, isEmpty);

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
        (requestID: 'request-1', mask: testSquareMaskBytes),
      ]);
      expect(calls.requestedMaskSources, [GenerationMaskSource.crop]);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    // Web の compute は同じスレッドで動くため、マスクを作り始める前に待ちの表示を描いていないと、押した後に画面が止まって見える (#302)
    testWidgets('「この範囲で作る」を押すと、マスクを作り始める前に待ちの表示を出し終えている', (tester) async {
      final shownOnSquareMaskStart = <({bool rangeButton, bool progress})>[];
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        letsUserChooseSubjectRange: true,
        sourcePhoto: readablePhoto,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async => null,
          createSquareMask: ({required photo, required crop}) async {
            shownOnSquareMaskStart.add((
              rangeButton: tester.any(find.text('この範囲で作る')),
              progress: tester.any(find.byType(CircularProgressIndicator)),
            ));
            return testSquareMaskBytes;
          },
          requestGeneration: savedGeneration(
            monsterID: 'm1',
            status: GenerationStatus.saved,
            resultRequestID: null,
          ),
          fetchGeneration: unexpectedFetch,
        ),
      );
      await tester.tap(find.text('この範囲で作る'));
      await tester.pumpAndSettle();
      expect(shownOnSquareMaskStart, [(rangeButton: false, progress: true)]);
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
        letsUserChooseSubjectRange: true,
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
            monsterID: 'm1',
            status: GenerationStatus.saved,
            resultRequestID: null,
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
        letsUserChooseSubjectRange: true,
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
        letsUserChooseSubjectRange: false,
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
        letsUserChooseSubjectRange: true,
        sourcePhoto: readablePhoto,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          createSubjectMask: ({required photo}) async => null,
          requestGeneration: ({required requestID}) async {
            if (++requestCount == 1) {
              throw const GenerationPhotoMissingException(
                message: '写真が見つかりません',
              );
            }
            return savedGeneration(
              monsterID: 'm1',
              status: GenerationStatus.saved,
              resultRequestID: null,
            )(requestID: requestID);
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
      expect(calls.uploadedRequestIDs, ['request-1', 'request-1']);
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
          monsterID: 'm1',
          status: GenerationStatus.saved,
          resultRequestID: 'earlier-request',
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
          monsterID: 'm1',
          status: GenerationStatus.duplicate,
          resultRequestID: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('もう図鑑にいます'), findsOneWidget);
    expect(dexStore.monsters, hasLength(1));
    expect(calls.loggedEvents, isEmpty);

    // 「手持ちを増やす」で生まれた画面と生成の画面を閉じ、撮る画面に戻る
    await tester.tap(find.text('手持ちを増やす'));
    await tester.pumpAndSettle();
    expect(find.text('開く'), findsOneWidget);
    expect(closedActions, [null]);
  });

  testWidgets(
    '途中の状態が続いた時はローディングのまま 5 秒ごとに同じ要求 ID で読み直し、生まれたらボタンを押さずに生まれた画面を開く',
    (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: false,
        settlesAfterOpening: false,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: pendingGeneration,
          fetchGeneration: fetchesInOrder(
            fetches: [
              pendingGeneration,
              processingGeneration,
              savedGeneration(
                monsterID: 'm1',
                status: GenerationStatus.saved,
                resultRequestID: null,
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('もう少し待ってね'), findsNothing);
      expect(calls.fetchedRequestIDs, isEmpty);

      await tester.pump(const Duration(seconds: 5));
      expect(calls.fetchedRequestIDs, ['request-1']);
      await tester.pump(const Duration(seconds: 5));
      expect(calls.fetchedRequestIDs, ['request-1', 'request-1']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('もう少し待ってね'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(calls.fetchedRequestIDs, ['request-1', 'request-1', 'request-1']);
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(calls.loggedEvents, hasLength(1));
    },
  );

  testWidgets('途中の状態が 40 秒続いたらもう少し待ってねを出し、もう一度確かめると読み直してまたローディングで待つ', (
    tester,
  ) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      settlesAfterOpening: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: pendingGeneration,
        fetchGeneration: pendingGeneration,
      ),
    );
    await tester.pump(const Duration(seconds: 39));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('もう少し待ってね'), findsNothing);
    expect(calls.fetchedRequestIDs, hasLength(7));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(calls.fetchedRequestIDs, hasLength(8));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('もう少し待ってね'), findsOneWidget);
    expect(find.text('もう一度確かめる'), findsOneWidget);
    expect(find.text('あとで見る'), findsOneWidget);

    await tester.tap(find.text('もう一度確かめる'));
    await tester.pump();
    await tester.pump();
    expect(calls.fetchedRequestIDs, hasLength(9));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('もう少し待ってね'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(calls.fetchedRequestIDs, hasLength(10));
    expect(calls.fetchedRequestIDs, everyElement('request-1'));

    await tester.pump(const Duration(seconds: 35));
    await tester.pump();
    expect(find.text('もう少し待ってね'), findsOneWidget);
  });

  testWidgets('読み直している間に画面を閉じたら、読み直しをやめる', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      settlesAfterOpening: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: pendingGeneration,
        fetchGeneration: pendingGeneration,
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(calls.fetchedRequestIDs, hasLength(1));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('開く'), findsOneWidget);
    await tester.pump(const Duration(seconds: 40));
    expect(calls.fetchedRequestIDs, hasLength(1));
  });

  testWidgets('使い回した別の要求が判定待ちの時は、使い回し先の要求 ID で読み直す', (tester) async {
    // 開く時の pumpAndSettle が、読み直しで生まれた後の画面まで進める
    await pumpGenerationScreen(
      tester: tester,
      startsFirstBattle: false,
      generator: fakeMonsterGenerator(
        calls: calls,
        albumPhoto: null,
        uploadError: null,
        requestGeneration: ({required requestID}) async =>
            const GenerationResult(
              requestID: 'earlier-request',
              status: GenerationStatus.pendingJudge,
              monsterID: null,
              rejectionReason: null,
              personDetected: false,
            ),
        fetchGeneration: savedGeneration(
          monsterID: 'm1',
          status: GenerationStatus.saved,
          resultRequestID: null,
        ),
      ),
    );
    expect(calls.fetchedRequestIDs, ['earlier-request']);
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
        requestGeneration: ({required requestID}) async => GenerationResult(
          requestID: requestID,
          status: GenerationStatus.rejected,
          monsterID: null,
          rejectionReason: GenerationRejectionReason.faceDetected,
          personDetected: false,
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
        requestGeneration: ({required requestID}) async => GenerationResult(
          requestID: requestID,
          status: GenerationStatus.failed,
          monsterID: null,
          rejectionReason: null,
          personDetected: false,
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
        requestGeneration: ({required requestID}) async {
          if (remainingFailureCount > 0) {
            remainingFailureCount--;
            throw Exception('deadline-exceeded');
          }
          return savedGeneration(
            monsterID: 'm1',
            status: GenerationStatus.saved,
            resultRequestID: null,
          )(requestID: requestID);
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('Exception: deadline-exceeded'), findsOneWidget);
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(calls.uploadedRequestIDs, ['request-1']);
    expect(calls.requestedRequestIDs, ['request-1', 'request-1']);
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
        requestGeneration: ({required requestID}) async {
          if (remainingFailureCount > 0) {
            remainingFailureCount--;
            throw const GenerationPhotoMissingException(
              message: '写真が見つかりません。写真を上げ直してください',
            );
          }
          return savedGeneration(
            monsterID: 'm1',
            status: GenerationStatus.saved,
            resultRequestID: null,
          )(requestID: requestID);
        },
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('写真が見つかりません。写真を上げ直してください'), findsOneWidget);
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(calls.uploadedRequestIDs, ['request-1', 'request-1']);
    expect(calls.requestedRequestIDs, ['request-1', 'request-1']);
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
        requestGeneration: ({required requestID}) =>
            throw StateError('requestGeneration は呼ばない'),
        fetchGeneration: unexpectedFetch,
      ),
    );
    expect(find.text('Bad state: ログインしていないため生成できません'), findsOneWidget);
    expect(find.text('もう一度試す'), findsOneWidget);
    expect(calls.requestedRequestIDs, isEmpty);
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
          monsterID: 'm1',
          status: GenerationStatus.saved,
          resultRequestID: null,
        ),
        fetchGeneration: unexpectedFetch,
      ),
    );
    await tester.tap(find.text('手持ちに入れる'));
    await tester.pumpAndSettle();
    expect(closedActions, [ResultScreenAction.openDex]);
    expect(dexStore.isInParty(monsterID: 'm1'), isTrue);
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
          requestGeneration: ({required requestID}) async => GenerationResult(
            requestID: requestID,
            status: GenerationStatus.rejected,
            monsterID: null,
            rejectionReason: GenerationRejectionReason.explicitContent,
            personDetected: false,
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

    testWidgets('判定待ち (pending_judge) の間は相手を探す表示を続け、40 秒続いたら「もう少し待ってね」に戻す', (
      tester,
    ) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        generator: fakeMonsterGenerator(
          calls: calls,
          albumPhoto: null,
          uploadError: null,
          requestGeneration: pendingGeneration,
          fetchGeneration: pendingGeneration,
        ),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('相手を探しています'), findsOneWidget);
      expect(find.text('もう少し待ってね'), findsNothing);
      // 読み直している間は、まだ生成に失敗していない
      expect(firstExperienceSteps(), ['photo_selected']);

      await tester.pump(const Duration(seconds: 40));
      await tester.pump();
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
          requestGeneration: ({required requestID}) async =>
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
              monsterID: 'm1',
              status: GenerationStatus.duplicate,
              resultRequestID: null,
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
        expect(dexStore.isInParty(monsterID: 'm1'), isTrue);
        // ログインが無い時の PvP の候補は null のため、CPU トレーナーが相手になる
        expect(find.textContaining(RegExp(r'^CPU .+ があらわれた$')), findsOneWidget);
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
          requestGeneration: pendingGeneration,
          // 40 秒の読み直し (8 回) の間は判定待ちのまま、「もう一度確かめる」の読み直しで生まれる
          fetchGeneration: fetchesInOrder(
            fetches: [
              ...List.filled(8, pendingGeneration),
              savedGeneration(
                monsterID: 'm1',
                status: GenerationStatus.saved,
                resultRequestID: null,
              ),
            ],
          ),
        ),
      );
      await pumpUntilResult(tester: tester);
      await tester.pump(const Duration(seconds: 40));
      await tester.pump();
      expect(find.text('もう少し待ってね'), findsOneWidget);

      await tester.tap(find.text('もう一度確かめる'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.fetchedRequestIDs, hasLength(9));
      expect(dexStore.isInParty(monsterID: 'm1'), isTrue);
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
          requestGeneration: ({required requestID}) async {
            dexStore.applyServerSnapshot(
              monsters: [
                generatedWaxMonster(monsterID: 'm0'),
                generatedWaxMonster(monsterID: 'm1'),
              ],
              partyMonsterIDs: ['m0'],
              definitions: definitionsWithWax(base: sampleData.definitions),
            );
            return GenerationResult(
              requestID: requestID,
              status: GenerationStatus.saved,
              monsterID: 'm1',
              rejectionReason: null,
              personDetected: false,
            );
          },
          fetchGeneration: unexpectedFetch,
        ),
      );
      await pumpUntilResult(tester: tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.byType(BattleScreen), findsNothing);
      expect(dexStore.isInParty(monsterID: 'm1'), isFalse);
      expect(firstExperienceSteps(), isNot(contains('matchmaking')));
    });

    /// [fetchProfile] だけを差し替えた、ログインが無い時の [PvpClient]。
    PvpClient pvpClientFetchingProfile({
      required Future<PlayerProfile?> Function() fetchProfile,
    }) {
      final signedOutClient = signedOutPvpClient(calls: RecordedPvpCalls());
      return PvpClient(
        fetchOpponents: signedOutClient.fetchOpponents,
        fetchDefinitions: signedOutClient.fetchDefinitions,
        reportMonster: signedOutClient.reportMonster,
        blockUser: signedOutClient.blockUser,
        fetchBattleRecord: signedOutClient.fetchBattleRecord,
        fetchProfile: fetchProfile,
        updateDisplayName: signedOutClient.updateDisplayName,
        updateIcon: signedOutClient.updateIcon,
      );
    }

    /// サーバーが m1 を保存して返す生成。
    MonsterGenerator savedM1Generator() => fakeMonsterGenerator(
      calls: calls,
      albumPhoto: null,
      uploadError: null,
      requestGeneration: savedGeneration(
        monsterID: 'm1',
        status: GenerationStatus.saved,
        resultRequestID: null,
      ),
      fetchGeneration: unexpectedFetch,
    );

    testWidgets('プロフィールは相手を決める間に並べて読み、読めたらバトルの画面に自分と CPU トレーナーの名前を渡す', (
      tester,
    ) async {
      final profileReply = Completer<PlayerProfile?>();
      var refreshedDefinitionsCount = 0;
      dexStore.connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) async {},
        saveSelectedMoveIDs: ({required monsterID, required moveIDs}) async {},
        refreshDefinitions: () async => refreshedDefinitionsCount++,
      );
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        pvpClient: pvpClientFetchingProfile(
          fetchProfile: () => profileReply.future,
        ),
        generator: savedM1Generator(),
      );
      await pumpUntilResult(tester: tester);
      // プロフィールの応答を待たずに定義の読み直しが済み、両方そろうまでは相手を出さない
      expect(refreshedDefinitionsCount, 1);
      expect(find.textContaining(RegExp(r'あらわれた$')), findsNothing);

      profileReply.complete((displayName: 'ばんざい', iconPath: null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining(RegExp(r'^CPU .+ があらわれた$')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      final battleScreen = tester.widget<BattleScreen>(
        find.byType(BattleScreen),
      );
      expect(battleScreen.playerProfile, (displayName: 'ばんざい', iconPath: null));
      expect(battleScreen.opponentDisplayName, startsWith('CPU '));
    });

    testWidgets('プロフィールを読めない時は札を出さずにバトルに進む', (tester) async {
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        pvpClient: pvpClientFetchingProfile(
          fetchProfile: () async => throw Exception('unavailable'),
        ),
        generator: savedM1Generator(),
      );
      await pumpUntilResult(tester: tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<BattleScreen>(find.byType(BattleScreen)).playerProfile,
        isNull,
      );
    });

    testWidgets('もう一度試した後に前の準備のプロフィールの失敗が届いても、読めたプロフィールをバトルの画面に渡す', (
      tester,
    ) async {
      final staleProfileReply = Completer<PlayerProfile?>();
      var fetchProfileCount = 0;
      var refreshDefinitionsCount = 0;
      dexStore.connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) async {},
        saveSelectedMoveIDs: ({required monsterID, required moveIDs}) async {},
        refreshDefinitions: () async {
          refreshDefinitionsCount += 1;
          if (refreshDefinitionsCount == 1) {
            throw Exception('master-unavailable');
          }
        },
      );
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        pvpClient: pvpClientFetchingProfile(
          fetchProfile: () {
            fetchProfileCount += 1;
            return fetchProfileCount == 1
                ? staleProfileReply.future
                : Future.value((displayName: 'ばんざい', iconPath: null));
          },
        ),
        generator: savedM1Generator(),
      );
      await pumpUntilResult(tester: tester);
      await tester.tap(find.text('もう一度試す'));
      await pumpUntilResult(tester: tester);
      expect(find.textContaining(RegExp(r'^CPU .+ があらわれた$')), findsOneWidget);

      staleProfileReply.completeError(Exception('late'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<BattleScreen>(find.byType(BattleScreen)).playerProfile,
        (displayName: 'ばんざい', iconPath: null),
      );
    });

    testWidgets('相手を決められない時はプロフィールの応答を待たずに元の例外の文言をそのまま出す', (tester) async {
      final profileReply = Completer<PlayerProfile?>();
      dexStore.connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) async {},
        saveSelectedMoveIDs: ({required monsterID, required moveIDs}) async {},
        refreshDefinitions: () async => throw Exception('master-unavailable'),
      );
      await pumpGenerationScreen(
        tester: tester,
        startsFirstBattle: true,
        pvpClient: pvpClientFetchingProfile(
          fetchProfile: () => profileReply.future,
        ),
        generator: savedM1Generator(),
      );
      await pumpUntilResult(tester: tester);
      expect(find.text('Exception: master-unavailable'), findsOneWidget);
      expect(find.byType(BattleScreen), findsNothing);
    });
  });
}
