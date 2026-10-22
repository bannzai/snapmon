import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/features/capture/generation_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  late DexStore dexStore;
  late RecordedGenerationCalls calls;

  /// [generator] の生成の画面を、閉じた時の [ResultScreenAction] を [closedActions] に残す画面から開く。
  Future<List<ResultScreenAction?>> pumpGenerationScreen({
    required WidgetTester tester,
    required MonsterGenerator generator,
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
                        sourcePhoto: testPhotoBytes,
                        photoSource: GenerationPhotoSource.album,
                        monsterGenerator: generator,
                        dexStore: dexStore,
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
    await tester.pumpAndSettle();
    return closedActions;
  }

  /// サーバーが [monsterId] のモンスターを保存して図鑑に届けた後に、[result] を返す生成。
  Future<GenerationResult> Function({required String requestId})
  savedGeneration({
    required String monsterId,
    required GenerationStatus status,
    required String? resultRequestId,
  }) =>
      ({required requestId}) async {
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
  });

  testWidgets('新しく保存された時は生まれた画面を開き、生成完了のイベントを 1 回送る', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
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

  testWidgets('同じ写真の別の要求の結果を使い回した時は、図鑑にいるモンスターを開きイベントを送らない', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
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

  testWidgets('判定待ちの時はもう少し待ってねを出し、同じ要求 ID で読み直して生まれたら生まれた画面を開く', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
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

  testWidgets('生成しなかった時は理由を出す', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
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

  testWidgets('呼び出しが例外で終わったらエラーをそのまま出し、もう一度試すと写真を送り直さず同じ要求 ID で呼ぶ', (tester) async {
    var remainingFailureCount = 1;
    await pumpGenerationScreen(
      tester: tester,
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

  testWidgets('ログインしていない時 (DEBUG でログインを飛ばした) は送る前のエラーをそのまま出し、生成を呼ばない', (tester) async {
    await pumpGenerationScreen(
      tester: tester,
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
}
