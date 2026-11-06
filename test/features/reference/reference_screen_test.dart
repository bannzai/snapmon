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
            'effectId': 'plastic_particle',
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
          onSelectTab: ({required tab}) {},
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
        attackerElementTypeId: 'metal',
        defenderElementTypeId: 'wood',
      ),
      '2',
    );
    expect(
      typeChartCellText(
        tester: tester,
        attackerElementTypeId: 'metal',
        defenderElementTypeId: 'metal',
      ),
      '0.5',
    );
    expect(
      typeChartCellText(
        tester: tester,
        attackerElementTypeId: 'metal',
        defenderElementTypeId: 'plant',
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

    // 金属の 2 番目の技 ねじこみ (metal_1b) は「硬い相手に強い」(倍率の最大 1.5 倍)
    final screwMove = find.byKey(const Key('reference-move-metal_1b'));
    expect(
      find.descendant(of: screwMove, matching: find.text('ねじこみ')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: screwMove,
        matching: find.text('威力 35  PP 35  Lv. 1 から'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: screwMove, matching: find.text('硬い相手に強い')),
      findsOneWidget,
    );

    final moveListScrollable = find.descendant(
      of: find.byKey(const Key('reference-move-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('reference-move-custom_rubber_1')),
      500,
      scrollable: moveListScrollable,
    );
    expect(find.text('ゴムだまはじき'), findsOneWidget);

    await tester.scrollUntilVisible(
      screwMove,
      -500,
      scrollable: moveListScrollable,
    );
    await tester.tap(screwMove);
    await tester.pumpAndSettle();

    expect(find.byType(MoveDetailScreen), findsOneWidget);
    expect(find.text('ねじこみ'), findsOneWidget);
    expect(find.text('相手の防御が自分の攻撃より高いと威力が上がる'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('move-special-effect-formula')))
          .data,
      '相手の防御 > 自分の攻撃 なら 150、それ以外は 100',
    );
    // 金属は木・紙・ガラスに 2 倍、金属・熱・石に 0.5 倍 (assets/master/master.json の typeChart)
    expect(find.text('よく効く'), findsOneWidget);
    expect(find.text('効きにくい'), findsOneWidget);
    expect(find.text('× 2'), findsNWidgets(3));
    expect(find.text('× 0.5'), findsNWidgets(3));
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
    expect(find.byKey(const Key('type-chart-metal-wood')), findsNothing);

    firstRefresh.completeError(StateError('Firestore に master が投入されていません'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('reference-error'))).data,
      'Bad state: Firestore に master が投入されていません',
    );
    expect(find.byKey(const Key('type-chart-metal-wood')), findsNothing);

    await tester.tap(find.text('もう一度読み込む'));
    await tester.pumpAndSettle();
    expect(refreshCount, 2);
    expect(find.byKey(const Key('reference-error')), findsNothing);
    expect(find.byKey(const Key('type-chart-metal-wood')), findsOneWidget);
  });
}
