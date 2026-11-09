import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/dex/dex_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/home/home_shell.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_colors.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 図鑑の画面を iPhone の画面の大きさ (モックの 390 × 844) で開き、シーンの切り替えを [selectedScenes] に残す。
  Future<void> pumpDexScreen({
    required WidgetTester tester,
    required DexStore dexStore,
    required List<HomeScene> selectedScenes,
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
        home: Scaffold(
          body: DexScreen(
            dexStore: dexStore,
            onSelectScene: ({required scene}) => selectedScenes.add(scene),
            onOpenSettings: () {},
            cardSharer: fakeCardSharer(
              calls: RecordedShareCalls(),
              artImage: null,
              shareResultStatus: ShareResultStatus.success,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// [name] の文字を持つ [index] 番目のカード (手持ちが先、「すべて」が後) の地の Material。
  Material monsterTileMaterial({
    required WidgetTester tester,
    required String name,
    required int index,
  }) => tester.widget<Material>(
    find
        .ancestor(
          of: find.text(name).at(index),
          matching: find.byType(Material),
        )
        .first,
  );

  testWidgets('手持ちと「すべて」のカードは同じ地の色で、手持ちにだけ黄緑の縁を付ける', (tester) async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters.take(1).toList());
    await pumpDexScreen(tester: tester, dexStore: dexStore, selectedScenes: []);

    final name = sampleData.monsters.first.definition.name;
    expect(find.text(name), findsNWidgets(2));
    final partyTile = monsterTileMaterial(tester: tester, name: name, index: 0);
    final allTile = monsterTileMaterial(tester: tester, name: name, index: 1);
    expect(partyTile.color, SnapmonColors.surface);
    expect(allTile.color, SnapmonColors.surface);
    expect(
      (partyTile.shape! as RoundedRectangleBorder).side.color,
      SnapmonColors.accent,
    );
    expect((allTile.shape! as RoundedRectangleBorder).side, BorderSide.none);
  });

  testWidgets('手持ちの空いた枠をタップすると手持ちに入っていないモンスターだけを出し、選ぶと手持ちに入れる', (tester) async {
    final firstMonster = sampleData.monsters[0];
    final fourthMonster = sampleData.monsters[3];
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters.take(4).toList());
    await dexStore.removeFromParty(monsterId: firstMonster.definition.id);
    await pumpDexScreen(tester: tester, dexStore: dexStore, selectedScenes: []);

    expect(find.byKey(const Key('dex-empty-party-slot')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dex-empty-party-slot')));
    await tester.pumpAndSettle();

    expect(find.text('手持ちに入れる'), findsOneWidget);
    expect(
      find.byKey(Key('dex-add-to-party-${firstMonster.definition.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('dex-add-to-party-${fourthMonster.definition.id}')),
      findsOneWidget,
    );
    for (final partyMonster in dexStore.party) {
      expect(
        find.byKey(Key('dex-add-to-party-${partyMonster.definition.id}')),
        findsNothing,
      );
    }

    await tester.tap(
      find.byKey(Key('dex-add-to-party-${fourthMonster.definition.id}')),
    );
    await tester.pumpAndSettle();

    expect(dexStore.isInParty(monsterId: fourthMonster.definition.id), isTrue);
    expect(dexStore.party, hasLength(3));
    expect(find.byKey(const Key('dex-empty-party-slot')), findsNothing);
  });

  testWidgets('手持ちに入れられるモンスターがいない時は、空いた枠をタップするとその旨を出す', (tester) async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters.take(2).toList());
    await pumpDexScreen(tester: tester, dexStore: dexStore, selectedScenes: []);

    await tester.tap(find.byKey(const Key('dex-empty-party-slot')));
    await tester.pumpAndSettle();

    expect(find.text('手持ちに入れられるモンスターがいません'), findsOneWidget);
    expect(find.byType(SimpleDialogOption), findsNothing);
  });

  testWidgets('手持ちの ID が図鑑より先に届いて枠が空いて見える間は、空いた枠をタップしても選ぶダイアログを出さない', (
    tester,
  ) async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: sampleData.monsters.take(2).toList(),
        partyMonsterIds: [
          for (final monster in sampleData.monsters.take(2))
            monster.definition.id,
          'monster-not-yet-in-dex',
        ],
        definitions: null,
      );
    await pumpDexScreen(tester: tester, dexStore: dexStore, selectedScenes: []);

    expect(find.byKey(const Key('dex-empty-party-slot')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dex-empty-party-slot')));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('撮る画面へは見出しのボタンではなく、画面の下の横長の「追加する」から開く', (tester) async {
    final selectedScenes = <HomeScene>[];
    await pumpDexScreen(
      tester: tester,
      dexStore: DexStore(definitions: sampleData.definitions),
      selectedScenes: selectedScenes,
    );

    expect(find.text('撮る'), findsNothing);
    final addButton = find.byKey(const Key('dex-add-monster'));
    expect(
      find.descendant(of: addButton, matching: find.text('追加する')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: addButton,
        matching: find.byIcon(Icons.photo_camera_outlined),
      ),
      findsOneWidget,
    );
    // 黄緑の地の上で読めるよう、文字はアイコンと同じ濃い色で描く
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(of: addButton, matching: find.text('追加する')),
          )
          .text
          .style
          ?.color,
      SnapmonColors.textOnCard,
    );
    // 横長: 左右の余白 20 を除いた画面の幅いっぱいで、画面の下半分に置く
    expect(tester.getSize(addButton).width, 390 - 20 * 2);
    expect(tester.getCenter(addButton).dy, greaterThan(844 / 2));

    await tester.tap(addButton);
    expect(selectedScenes, [HomeScene.capture]);
  });

  testWidgets('一番下までスクロールすると、最後の行のカードは「追加する」ボタンに隠れない', (tester) async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    await pumpDexScreen(tester: tester, dexStore: dexStore, selectedScenes: []);
    // 見本の 6 体は 844 の高さにほぼ収まりスクロールしないため、画面を低くして一番下までスクロールさせる
    tester.view.physicalSize = const Size(390, 600);
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(
      tester
          .getBottomLeft(
            find
                .ancestor(
                  of: find.text(sampleData.monsters.last.definition.name).last,
                  matching: find.byType(Material),
                )
                .first,
          )
          .dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('dex-add-monster'))).dy,
      ),
    );
  });
}
