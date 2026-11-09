import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/dex/dex_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/reference/move_detail_screen.dart';
import 'package:snapmon/features/reference/reference_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../card_sharer_fixture.dart';

void main() {
  /// master の最新の版 (アプリが Firestore の master/{version} から読むものと同じファイル) に、
  /// 図鑑のモンスターが参照するその場で作った定義 (属性 1 つと技 1 つ) を足した定義。
  final definitions = mergeMasterData(
    base: MasterData.fromJson(
      json:
          jsonDecode(File('assets/master/master.json').readAsStringSync())
              as Map<String, dynamic>,
    ),
    additional: MasterData.fromJson(
      json: {
        'version': 1,
        'elementTypes': [
          {'id': 'custom_rubber', 'displayName': 'ゴム'},
        ],
        'moves': [
          {
            'id': 'custom_rubber_1',
            'displayName': 'ゴムだまはじき',
            'elementTypeId': 'custom_rubber',
            'power': 40,
            'powerPoints': 30,
            'category': 'attack',
            'effectId': 'machine_particle',
            'learnableLevelMinimum': 1,
            'learnableLevelMaximum': 30,
          },
        ],
      },
    ),
  );

  /// [home] を iPhone の画面の大きさ (モックの 390 × 844) で開く。
  Future<void> pumpApp({
    required WidgetTester tester,
    required Widget home,
  }) async {
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
        home: home,
      ),
    );
  }

  /// 相性表の、技の属性 [attackerElementTypeId] から受ける側の属性 [defenderElementTypeId] へのマスに出ている倍率の文字。
  String typeChartCellText({
    required WidgetTester tester,
    required String attackerElementTypeId,
    required String defenderElementTypeId,
  }) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(
            Key('type-chart-$attackerElementTypeId-$defenderElementTypeId'),
          ),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('図鑑の画面から開き、相性表に master の倍率とその場で作った属性の等倍を出す', (tester) async {
    await pumpApp(
      tester: tester,
      home: Scaffold(
        body: DexScreen(
          dexStore: DexStore(definitions: definitions),
          onSelectScene: ({required scene}) {},
          onOpenSettings: () {},
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('dex-open-reference')));
    await tester.pumpAndSettle();

    expect(find.byType(ReferenceScreen), findsOneWidget);
    expect(find.text('相性表'), findsOneWidget);
    expect(
      typeChartCellText(
        tester: tester,
        attackerElementTypeId: 'steel',
        defenderElementTypeId: 'ice',
      ),
      '2',
    );
    expect(
      typeChartCellText(
        tester: tester,
        attackerElementTypeId: 'steel',
        defenderElementTypeId: 'water',
      ),
      '0.5',
    );
    expect(
      typeChartCellText(
        tester: tester,
        attackerElementTypeId: 'steel',
        defenderElementTypeId: 'grass',
      ),
      '1',
    );
    // その場で作った属性も表に並べ、相性は既存の全属性と等倍 (ADR 0001「master に無い属性・技」)
    for (final elementType in definitions.elementTypes) {
      expect(
        typeChartCellText(
          tester: tester,
          attackerElementTypeId: 'custom_rubber',
          defenderElementTypeId: elementType.id,
        ),
        '1',
      );
      expect(
        typeChartCellText(
          tester: tester,
          attackerElementTypeId: elementType.id,
          defenderElementTypeId: 'custom_rubber',
        ),
        '1',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('技の一覧にその場で作った技も出し、技をタップすると特殊効果の式と相性の詳細を開く', (tester) async {
    await pumpApp(
      tester: tester,
      home: ReferenceScreen(dexStore: DexStore(definitions: definitions)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('技の一覧'));
    await tester.pumpAndSettle();

    // 炎の 2 番目の技 ゆげのもや (fire_1b) は「先に動くと強い」(倍率の最大 1.3 倍)。炎は一覧の先頭の属性で、
    // 23 属性 276 件の一覧でも最初の画面に描かれる
    final steamMove = find.byKey(const Key('reference-move-fire_1b'));
    expect(
      find.descendant(of: steamMove, matching: find.text('ゆげのもや')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: steamMove,
        matching: find.text('威力 35  PP 35  Lv. 1 から'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: steamMove, matching: find.text('先に動くと強い')),
      findsOneWidget,
    );

    final moveListScrollable = find.descendant(
      of: find.byKey(const Key('reference-move-list')),
      matching: find.byType(Scrollable),
    );
    // その場で作った技は 23 属性 460 件 (版 9) の後ろに出るため、既定の 50 回より多くスクロールする
    await tester.scrollUntilVisible(
      find.byKey(const Key('reference-move-custom_rubber_1')),
      500,
      scrollable: moveListScrollable,
      maxScrolls: 400,
    );
    expect(find.text('ゴムだまはじき'), findsOneWidget);

    await tester.scrollUntilVisible(
      steamMove,
      -500,
      scrollable: moveListScrollable,
      maxScrolls: 400,
    );
    // scrollUntilVisible は要素が作られた (画面の外の cache の範囲でも) 時点で止まるため、タップの前に画面の中へ入れる
    await tester.ensureVisible(steamMove);
    await tester.pumpAndSettle();
    await tester.tap(steamMove);
    await tester.pumpAndSettle();

    expect(find.byType(MoveDetailScreen), findsOneWidget);
    expect(find.text('ゆげのもや'), findsOneWidget);
    expect(find.text('先に行動すると威力が上がる'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('move-special-effect-formula')))
          .data,
      '相手より先に行動した なら 130、それ以外は 100',
    );
    // 炎は草・木・虫・氷・菓子・紙に 2 倍、水・土・魚・竜に 0.5 倍 (assets/master/master.json の typeChart)
    expect(find.text('よく効く'), findsOneWidget);
    expect(find.text('効きにくい'), findsOneWidget);
    expect(find.text('× 2'), findsNWidgets(6));
    expect(find.text('× 0.5'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('技の一覧に、別の技が置き換えた補助技を出さず、置き換えた攻撃技と置き換えていない補助技を出す (#257)', (
    tester,
  ) async {
    await pumpApp(
      tester: tester,
      home: ReferenceScreen(dexStore: DexStore(definitions: definitions)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('技の一覧'));
    await tester.pumpAndSettle();

    final moveListScrollable = find.descendant(
      of: find.byKey(const Key('reference-move-list')),
      matching: find.byType(Scrollable),
    );
    // 炎 (一覧の先頭の属性) の行を、炎の最後の技 fire_a7 が出るまで少しずつ送り、途中のどの画面にも fire_s1 が無いことを確かめる
    var sawRecoverySupport = false;
    for (
      var step = 0;
      step < 100 &&
          find.byKey(const Key('reference-move-fire_a7')).evaluate().isEmpty;
      step++
    ) {
      expect(find.byKey(const Key('reference-move-fire_s1')), findsNothing);
      sawRecoverySupport |= find
          .byKey(const Key('reference-move-fire_s3'))
          .evaluate()
          .isNotEmpty;
      await tester.drag(moveListScrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('reference-move-fire_a7')), findsOneWidget);
    expect(find.byKey(const Key('reference-move-fire_s1')), findsNothing);
    sawRecoverySupport |= find
        .byKey(const Key('reference-move-fire_s3'))
        .evaluate()
        .isNotEmpty;
    expect(sawRecoverySupport, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('開いた時に最新の master を読み直し、失敗したら古い表を出さずにエラーとやり直しを出す', (tester) async {
    final dexStore = DexStore(definitions: definitions);
    var refreshCount = 0;
    final firstRefresh = Completer<void>();
    dexStore.connectServer(
      savePartyMonsterIds: ({required monsterIds}) async {},
      refreshDefinitions: () {
        refreshCount++;
        return refreshCount == 1 ? firstRefresh.future : Future.value();
      },
    );
    await pumpApp(
      tester: tester,
      home: ReferenceScreen(dexStore: dexStore),
    );

    expect(refreshCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('type-chart-steel-ice')), findsNothing);

    firstRefresh.completeError(StateError('Firestore に master が投入されていません'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('reference-error'))).data,
      'Bad state: Firestore に master が投入されていません',
    );
    expect(find.byKey(const Key('type-chart-steel-ice')), findsNothing);

    await tester.tap(find.text('もう一度読み込む'));
    await tester.pumpAndSettle();
    expect(refreshCount, 2);
    expect(find.byKey(const Key('reference-error')), findsNothing);
    expect(find.byKey(const Key('type-chart-steel-ice')), findsOneWidget);
  });
}
