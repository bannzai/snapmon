import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/render_widget_png.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/monster_ui/monster_parts.dart';
import 'package:snapmon/common_ui/storage_image.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

/// アプリが同梱する書体 (pubspec.yaml の fonts) の family とファイル。
/// テストの既定の書体は字幅が実際と違うため、はみ出しを実際の書体で確かめる。
const Map<String, List<String>> _bundledFontPaths = {
  'DelaGothicOne': ['assets/fonts/dela_gothic_one/DelaGothicOne-Regular.ttf'],
  'ZenKakuGothicNew': [
    'assets/fonts/zen_kaku_gothic_new/ZenKakuGothicNew-Regular.ttf',
    'assets/fonts/zen_kaku_gothic_new/ZenKakuGothicNew-Bold.ttf',
  ],
};

/// PNG の [pngBytes] の画素の幅と高さ (IHDR に書かれた値)。
(int, int) _pngSize({required Uint8List pngBytes}) {
  final byteData = ByteData.sublistView(pngBytes);
  return (byteData.getUint32(16), byteData.getUint32(20));
}

void main() {
  final sampleData = loadSampleDataFixture();
  const artPath = 'monsters/sample-mugmon/art.png';
  const sourcePhotoReference = 'users/uid-1/photos/original-photo';

  /// 切り出した画像と元の写真を持つ 1 体。
  final monsterWithArt = ownedMonsterWithArt(
    monster: sampleData.monsterByID(monsterID: 'sample-mugmon'),
    artPath: artPath,
    sourcePhotoReference: sourcePhotoReference,
  );

  /// [format] の [card] を、論理の大きさの枠に入れて開く。
  Future<void> pumpCard({
    required WidgetTester tester,
    required Widget card,
    required ShareCardFormat format,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: SizedBox.fromSize(size: format.logicalSize, child: card),
        ),
      ),
    );
  }

  /// 描いたカードの絵が、Storage から読む部品を使わず、渡した切り出した画像 [artImage] だけであることを確かめる。
  void expectOnlyArtImage({
    required WidgetTester tester,
    required ui.Image artImage,
  }) {
    expect(find.byType(StorageImage), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    final monsterArtImages = find.byType(MonsterArtImage);
    expect(monsterArtImages, findsOneWidget);
    expect(
      tester.widget<MonsterArtImage>(monsterArtImages).artImage,
      same(artImage),
    );
  }

  /// 8×8 の切り出した画像の代わり。テストの終わりに dispose する。
  Future<ui.Image> createArtImage({required WidgetTester tester}) async {
    final artImage = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(artImage.dispose);
    return artImage;
  }

  /// 描いたカードに、名前と図鑑の文章が AI の生成である表示が無いことを確かめる (開示は利用規約・プライバシーポリシー・ストアの説明文で行うため)。
  void expectNoGeneratedByAiText() {
    expect(find.textContaining('AI が'), findsNothing);
  }

  group('カードの絵は渡した切り出した画像だけで描き、AI の生成の表示を描かない', () {
    for (final format in ShareCardFormat.values) {
      testWidgets('図鑑のカード (${format.name})', (tester) async {
        final artImage = await createArtImage(tester: tester);
        await pumpCard(
          tester: tester,
          card: MonsterShareCard(
            monster: monsterWithArt,
            artImagesByPath: {artPath: artImage},
            definitions: sampleData.definitions,
            format: format,
          ),
          format: format,
        );
        expectOnlyArtImage(tester: tester, artImage: artImage);
        expect(find.textContaining(sourcePhotoReference), findsNothing);
        expectNoGeneratedByAiText();
        expect(find.text('SnapMonster'), findsOneWidget);
      });

      testWidgets('バトルの結果のカード (${format.name})', (tester) async {
        final artImage = await createArtImage(tester: tester);
        await pumpCard(
          tester: tester,
          card: BattleResultShareCard(
            winner: BattleSideID.player,
            playerParty: [monsterWithArt],
            appliedLevels: {monsterWithArt.definition.id: 8},
            opponentParty: [
              sampleData.monsterByID(monsterID: 'sample-ringora'),
            ],
            artImagesByPath: {artPath: artImage},
            definitions: sampleData.definitions,
            format: format,
          ),
          format: format,
        );
        expectOnlyArtImage(tester: tester, artImage: artImage);
        expect(find.textContaining(sourcePhotoReference), findsNothing);
        expectNoGeneratedByAiText();
        expect(find.text('Lv. 7 → 8'), findsOneWidget);
        expect(find.text('SnapMonster'), findsOneWidget);
      });
    }
  });

  group('バトルの結果のカードに技の枠の技を描く', () {
    /// マグモン (見本の Lv. 7。Lv. 1 の技が 4 つ、Lv. 15 で覚える技が 2 つ) を [level] と [selectedMoveIDs] にした 1 体。
    OwnedMonster mugmon({
      required int level,
      required List<String>? selectedMoveIDs,
    }) => OwnedMonster(
      definition: monsterWithArt.definition,
      level: level,
      actionCardMoveIDs: const [],
      selectedMoveIDs: selectedMoveIDs,
      artPath: monsterWithArt.artPath,
      definitionIDs: monsterWithArt.definitionIDs,
      decoration: monsterWithArt.decoration,
      decorationVersion: monsterWithArt.decorationVersion,
    );

    /// [monster] 1 体の勝ったバトルの結果のカードを [format] で開く。
    Future<void> pumpBattleResultCard({
      required WidgetTester tester,
      required OwnedMonster monster,
      required Map<String, int> appliedLevels,
      required ShareCardFormat format,
    }) async => pumpCard(
      tester: tester,
      card: BattleResultShareCard(
        winner: BattleSideID.player,
        playerParty: [monster],
        appliedLevels: appliedLevels,
        opponentParty: [sampleData.monsterByID(monsterID: 'sample-ringora')],
        artImagesByPath: {artPath: await createArtImage(tester: tester)},
        definitions: sampleData.definitions,
        format: format,
      ),
      format: format,
    );

    for (final format in ShareCardFormat.values) {
      testWidgets('技の枠の 4 つの技の名前を描く (${format.name})', (tester) async {
        await pumpBattleResultCard(
          tester: tester,
          monster: mugmon(level: 7, selectedMoveIDs: null),
          appliedLevels: const {},
          format: format,
        );
        for (final moveName in ['ほかほかタッチ', 'ブリキパンチ', 'ゆげのもや', 'ねじこみ']) {
          expect(find.text(moveName), findsOneWidget);
        }
        // Lv. 15 で覚える技はまだ描かない
        expect(find.text('ねつふうしゃ'), findsNothing);
        expect(find.text('スチールプレス'), findsNothing);
      });

      testWidgets('確定したレベルがあれば、上がった後のレベルの技の枠を描く (${format.name})', (
        tester,
      ) async {
        final monster = mugmon(level: 14, selectedMoveIDs: null);
        await pumpBattleResultCard(
          tester: tester,
          monster: monster,
          appliedLevels: {monster.definition.id: 15},
          format: format,
        );
        expect(find.text('Lv. 14 → 15'), findsOneWidget);
        // Lv. 15 で覚えた 2 つが、一番古い 2 つ (ほかほかタッチ・ブリキパンチ) の枠に入る
        for (final moveName in ['ねつふうしゃ', 'スチールプレス', 'ゆげのもや', 'ねじこみ']) {
          expect(find.text(moveName), findsOneWidget);
        }
        expect(find.text('ほかほかタッチ'), findsNothing);
        expect(find.text('ブリキパンチ'), findsNothing);
      });

      testWidgets('レベルが確定していなければ、バトルの前のレベルの技の枠を描く (${format.name})', (
        tester,
      ) async {
        await pumpBattleResultCard(
          tester: tester,
          monster: mugmon(level: 14, selectedMoveIDs: null),
          appliedLevels: const {},
          format: format,
        );
        expect(find.text('Lv. 14'), findsOneWidget);
        expect(find.text('ほかほかタッチ'), findsOneWidget);
        expect(find.text('ねつふうしゃ'), findsNothing);
      });

      testWidgets('対戦の前に選んだ技だけを選んだ順に描く (${format.name})', (tester) async {
        await pumpBattleResultCard(
          tester: tester,
          monster: mugmon(level: 7, selectedMoveIDs: ['steel_1b', 'fire_1']),
          appliedLevels: const {},
          format: format,
        );
        // 技を 2 列に並べる形では同じ行の左右に、1 列に並べる形では上下に並ぶ
        final firstMoveTopLeft = tester.getTopLeft(find.text('ねじこみ'));
        final secondMoveTopLeft = tester.getTopLeft(find.text('ほかほかタッチ'));
        expect(
          firstMoveTopLeft.dy < secondMoveTopLeft.dy ||
              (firstMoveTopLeft.dy == secondMoveTopLeft.dy &&
                  firstMoveTopLeft.dx < secondMoveTopLeft.dx),
          isTrue,
        );
        expect(find.text('ブリキパンチ'), findsNothing);
        expect(find.text('ゆげのもや'), findsNothing);
      });
    }
  });

  group('カードを PNG にする', () {
    setUpAll(() async {
      for (final entry in _bundledFontPaths.entries) {
        final fontLoader = FontLoader(entry.key);
        for (final path in entry.value) {
          fontLoader.addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          );
        }
        await fontLoader.load();
      }
      // 属性のアイコン (Material のアイコン)。読まないと、書き出す PNG のアイコンが四角になる
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });

    /// 見本の定義の技のうち名前の長い 4 つ (長い順)。
    final longestNamedMoves =
        ([...sampleData.definitions.moves]..sort(
              (first, second) =>
                  second.displayName.length.compareTo(first.displayName.length),
            ))
            .take(4)
            .toList();

    /// 見本のモンスターのうち名前の長い 3 体に、属性を 4 つずつと、名前の長い 4 つの技 ([longestNamedMoves]) を持たせたもの
    /// (文字が入りにくい手持ち)。
    List<OwnedMonster> longestNamedMonsters() =>
        ([...sampleData.monsters]..sort(
              (first, second) => second.definition.name.length.compareTo(
                first.definition.name.length,
              ),
            ))
            .take(3)
            .map(
              (monster) => OwnedMonster(
                definition: MonsterDefinition(
                  id: monster.definition.id,
                  sourcePhotoReference: monster.definition.sourcePhotoReference,
                  name: monster.definition.name,
                  encyclopediaText: monster.definition.encyclopediaText,
                  elementTypeIDs: [
                    for (final elementType
                        in sampleData.definitions.elementTypes.take(4))
                      elementType.id,
                  ],
                  learnset: [
                    for (final move in longestNamedMoves)
                      LearnsetEntry(moveID: move.id, unlockLevel: 1),
                  ],
                  baseStats: monster.definition.baseStats,
                  individualValues: monster.definition.individualValues,
                  statCalculationVersion:
                      monster.definition.statCalculationVersion,
                  masterVersion: monster.definition.masterVersion,
                ),
                level: monster.level,
                actionCardMoveIDs: const [],
                selectedMoveIDs: null,
                artPath: monster.artPath,
                definitionIDs: monster.definitionIDs,
                decoration: monster.decoration,
                decorationVersion: monster.decorationVersion,
              ),
            )
            .toList();

    /// [monsters] の切り出した画像のパスごとに、[createArtImage] の画像を引けるようにしたもの (見本のモンスターは同梱の画像を持つため)。
    Future<Map<String, ui.Image>> createArtImagesByPath({
      required WidgetTester tester,
      required List<OwnedMonster> monsters,
    }) async {
      final artImage = await createArtImage(tester: tester);
      return {for (final monster in monsters) monster.artPath!: artImage};
    }

    for (final name in ['プカプック', 'ハーブポット']) {
      testWidgets('縦長の図鑑のカードで、属性が 2 つの $name の名前を省略しない', (tester) async {
        await pumpCard(
          tester: tester,
          card: MonsterShareCard(
            monster: OwnedMonster(
              definition: MonsterDefinition(
                id: monsterWithArt.definition.id,
                sourcePhotoReference:
                    monsterWithArt.definition.sourcePhotoReference,
                name: name,
                encyclopediaText: monsterWithArt.definition.encyclopediaText,
                elementTypeIDs: [
                  for (final elementType
                      in sampleData.definitions.elementTypes.take(2))
                    elementType.id,
                ],
                learnset: monsterWithArt.definition.learnset,
                baseStats: monsterWithArt.definition.baseStats,
                individualValues: monsterWithArt.definition.individualValues,
                statCalculationVersion:
                    monsterWithArt.definition.statCalculationVersion,
                masterVersion: monsterWithArt.definition.masterVersion,
              ),
              level: monsterWithArt.level,
              actionCardMoveIDs: const [],
              selectedMoveIDs: null,
              artPath: monsterWithArt.artPath,
              definitionIDs: monsterWithArt.definitionIDs,
              decoration: monsterWithArt.decoration,
              decorationVersion: monsterWithArt.decorationVersion,
            ),
            artImagesByPath: {artPath: await createArtImage(tester: tester)},
            definitions: sampleData.definitions,
            format: ShareCardFormat.portrait,
          ),
          format: ShareCardFormat.portrait,
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(name))
              .didExceedMaxLines,
          isFalse,
        );
      });
    }

    testWidgets('描く間のエラーを握りつぶさず、PNG にせずに投げる', (tester) async {
      Object? renderError;
      await tester.runAsync(() async {
        try {
          await renderWidgetToPng(
            view: tester.view,
            card: Builder(builder: (context) => throw StateError('カードを描けない')),
            format: ShareCardFormat.portrait,
          );
        } catch (error) {
          renderError = error;
        }
      });
      expect(renderError, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    /// [card] を [locale] の文言で描けるようにする (ShareCardButton がカードを描く時と同じ包み方)。
    Widget localizedCard({required Locale locale, required Widget card}) =>
        Localizations(
          locale: locale,
          delegates: AppLocalizations.localizationsDelegates,
          child: card,
        );

    for (final locale in AppLocalizations.supportedLocales) {
      for (final format in ShareCardFormat.values) {
        final expectedSize = (
          (format.logicalSize.width * format.pixelRatio).round(),
          (format.logicalSize.height * format.pixelRatio).round(),
        );

        testWidgets(
          '図鑑のカード ($locale) が ${expectedSize.$1}×${expectedSize.$2} の PNG になり、はみ出さない',
          (tester) async {
            final monster = longestNamedMonsters().first;
            final artImagesByPath = await createArtImagesByPath(
              tester: tester,
              monsters: [monster],
            );
            final pngBytes = await tester.runAsync(
              () => renderWidgetToPng(
                view: tester.view,
                card: localizedCard(
                  locale: locale,
                  card: MonsterShareCard(
                    monster: monster,
                    artImagesByPath: artImagesByPath,
                    definitions: sampleData.definitions,
                    format: format,
                  ),
                ),
                format: format,
              ),
            );
            expect(_pngSize(pngBytes: pngBytes!), expectedSize);
            // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
            expect(tester.takeException(), isNull);
          },
        );

        for (final (winner, partySize) in [
          for (final winner in BattleSideID.values)
            for (var partySize = 1; partySize <= maximumPartySize; partySize++)
              (winner, partySize),
        ]) {
          testWidgets(
            '手持ち $partySize 体のバトルの結果のカード (${winner.name}・$locale) が ${expectedSize.$1}×${expectedSize.$2} の PNG になり、はみ出さない',
            (tester) async {
              final playerParty = longestNamedMonsters()
                  .take(partySize)
                  .toList();
              final artImagesByPath = await createArtImagesByPath(
                tester: tester,
                monsters: playerParty,
              );
              final pngBytes = await tester.runAsync(
                () => renderWidgetToPng(
                  view: tester.view,
                  card: localizedCard(
                    locale: locale,
                    card: BattleResultShareCard(
                      winner: winner,
                      playerParty: playerParty,
                      appliedLevels: {
                        for (final monster in playerParty)
                          monster.definition.id: monster.level + 1,
                      },
                      opponentParty: playerParty,
                      artImagesByPath: artImagesByPath,
                      definitions: sampleData.definitions,
                      format: format,
                    ),
                  ),
                  format: format,
                ),
              );
              expect(_pngSize(pngBytes: pngBytes!), expectedSize);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    /// 手持ちの数ごとの、絵の一辺の下限 (論理の大きさ)。直す前の縦長の絵は手持ちの数によらず 92 で、
    /// 横長の 3 体は枠の幅 (約 112) が上限のため 100 にした (https://github.com/bannzai/snapmon/issues/346 )。
    const minimumArtSizes = {
      ShareCardFormat.portrait: {1: 200.0, 2: 150.0, 3: 93.0},
      ShareCardFormat.landscape: {1: 200.0, 2: 150.0, 3: 100.0},
    };

    /// 見本のモンスターのうち、Lv. 1 の技が 4 つで、見本のレベルではまだ次の技を覚えていない 3 体
    /// (技の枠が Lv. 1 の 4 つの技のままの、標準の長さの名前と技の手持ち)。
    List<OwnedMonster> typicalMonsters() => [
      for (final monsterID in [
        'sample-mugmon',
        'sample-petbottler',
        'sample-ringora',
      ])
        sampleData.monsterByID(monsterID: monsterID),
    ];

    for (final format in ShareCardFormat.values) {
      for (var partySize = 1; partySize <= maximumPartySize; partySize++) {
        /// 手持ち [playerParty] のバトルの結果のカードを [format] で開く。
        Future<void> pumpBattleResultCard({
          required WidgetTester tester,
          required List<OwnedMonster> playerParty,
        }) async => pumpCard(
          tester: tester,
          card: BattleResultShareCard(
            winner: BattleSideID.player,
            playerParty: playerParty,
            appliedLevels: const {},
            opponentParty: playerParty,
            artImagesByPath: await createArtImagesByPath(
              tester: tester,
              monsters: playerParty,
            ),
            definitions: sampleData.definitions,
            format: format,
          ),
          format: format,
        );

        testWidgets(
          '手持ち $partySize 体のバトルの結果のカード (${format.name}) は、文字が入りにくい手持ちでも絵を大きく描き、名前と技をカードの中に切らずに描く',
          (tester) async {
            final playerParty = longestNamedMonsters().take(partySize).toList();
            await pumpBattleResultCard(
              tester: tester,
              playerParty: playerParty,
            );
            expect(tester.takeException(), isNull);
            final cardRect = tester.getRect(find.byType(BattleResultShareCard));
            final artImages = find.byType(MonsterArtImage);
            expect(artImages, findsNWidgets(partySize));
            for (var index = 0; index < partySize; index++) {
              final artRect = tester.getRect(artImages.at(index));
              expect(artRect.width, closeTo(artRect.height, 0.01));
              expect(
                artRect.width,
                greaterThanOrEqualTo(minimumArtSizes[format]![partySize]!),
              );
              expect(cardRect.contains(artRect.topLeft), isTrue);
              expect(cardRect.contains(artRect.bottomRight), isTrue);
            }
            for (final text in [
              for (final monster in playerParty) monster.definition.name,
              for (final move in longestNamedMoves) move.displayName,
            ]) {
              // 相手の名前は「VS 〇〇・〇〇」の 1 つの文字列のため、名前だけの文字列は自分の手持ちの枠にしか無い
              expect(find.text(text), findsAtLeastNWidgets(1));
              for (final element in find.text(text).evaluate()) {
                final paragraph = element.renderObject! as RenderParagraph;
                expect(paragraph.didExceedMaxLines, isFalse);
                expect(
                  cardRect.contains(paragraph.localToGlobal(Offset.zero)),
                  isTrue,
                );
                expect(
                  cardRect.contains(
                    paragraph.localToGlobal(
                      paragraph.size.bottomRight(Offset.zero),
                    ),
                  ),
                  isTrue,
                );
              }
            }
            // 技は手持ちの全員が同じ 4 つを持つ
            for (final move in longestNamedMoves) {
              expect(find.text(move.displayName), findsNWidgets(partySize));
            }
          },
        );

        testWidgets(
          '手持ち $partySize 体のバトルの結果のカード (${format.name}) は、標準の手持ちの技の名前を元の 6 割以上の大きさで描く',
          (tester) async {
            final playerParty = typicalMonsters().take(partySize).toList();
            await pumpBattleResultCard(
              tester: tester,
              playerParty: playerParty,
            );
            for (final monster in playerParty) {
              for (final learnsetEntry in monster.definition.learnset.where(
                (learnsetEntry) => learnsetEntry.unlockLevel == 1,
              )) {
                final moveName = find.text(
                  sampleData.definitions
                      .moveByID(moveID: learnsetEntry.moveID)
                      .displayName,
                );
                expect(moveName, findsOneWidget);
                expect(
                  tester.getRect(moveName).height /
                      tester.getSize(moveName).height,
                  greaterThanOrEqualTo(0.6),
                );
              }
            }
          },
        );
      }
    }

    // 見た目を人と agent が確かめるための画像。環境変数 SHARE_CARD_PNG_DIRECTORY があれば、見本の手持ち 1〜3 体の
    // バトルの結果のカードを見本の絵で描いて書き出す (flutter-ci.yml が成果物 share-cards に残す)。
    if (Platform.environment['SHARE_CARD_PNG_DIRECTORY']
        case final pngDirectory?) {
      for (final format in ShareCardFormat.values) {
        for (var partySize = 1; partySize <= maximumPartySize; partySize++) {
          testWidgets('手持ち $partySize 体のバトルの結果のカード (${format.name}) を書き出す', (
            tester,
          ) async {
            final playerParty = typicalMonsters().take(partySize).toList();
            final pngBytes = await tester.runAsync(() async {
              final artImagesByPath = {
                for (final monster in playerParty)
                  monster.artPath!: await decodeImageFromList(
                    File(monster.artPath!).readAsBytesSync(),
                  ),
              };
              try {
                return await renderWidgetToPng(
                  view: tester.view,
                  card: localizedCard(
                    locale: const Locale('ja'),
                    card: BattleResultShareCard(
                      winner: BattleSideID.player,
                      playerParty: playerParty,
                      appliedLevels: {
                        for (final monster in playerParty)
                          monster.definition.id: monster.level + 1,
                      },
                      opponentParty: sampleData.monsters
                          .skip(maximumPartySize)
                          .take(partySize)
                          .toList(),
                      artImagesByPath: artImagesByPath,
                      definitions: sampleData.definitions,
                      format: format,
                    ),
                  ),
                  format: format,
                );
              } finally {
                for (final artImage in artImagesByPath.values) {
                  artImage.dispose();
                }
              }
            });
            File('$pngDirectory/battle-result-${format.name}-$partySize.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(pngBytes!);
          });
        }
      }
    }
  });
}
