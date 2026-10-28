import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/share/card_sharer.dart';

/// テスト用の [CardSharer] が受け取った呼び出し。
class RecordedShareCalls {
  /// loadArtImage に渡された画像のパス (呼ばれた順)。
  final List<String> loadedArtPaths = [];

  /// renderPng に渡されたカードと形 (呼ばれた順)。
  final List<({Widget card, ShareCardFormat format})> renderedCards = [];

  /// shareImage に渡されたファイル名と文章 (呼ばれた順)。
  final List<({String fileName, String text})> sharedImages = [];

  /// logEvent に渡されたイベントとパラメータ (呼ばれた順)。
  final List<({AnalyticsEvent event, Map<String, Object>? parameters})>
  loggedEvents = [];
}

/// 1×1 の透明な PNG。共有の前に見せる画像として読める値にするため。
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// [monster] を、写真から切り出した画像 [artPath] と元の写真 [sourcePhotoReference] を持つ 1 体にしたもの。
/// 見本のモンスターは元の写真を持たないため、共有のカードが元の写真を読まないことの確認に使う。
OwnedMonster ownedMonsterWithArt({
  required OwnedMonster monster,
  required String artPath,
  required String sourcePhotoReference,
}) {
  final definition = monster.definition;
  return OwnedMonster(
    definition: MonsterDefinition(
      id: definition.id,
      sourcePhotoReference: sourcePhotoReference,
      name: definition.name,
      encyclopediaText: definition.encyclopediaText,
      elementTypeIds: definition.elementTypeIds,
      learnset: definition.learnset,
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      statCalculationVersion: definition.statCalculationVersion,
      masterVersion: definition.masterVersion,
    ),
    level: monster.level,
    artPath: artPath,
    definitionIds: monster.definitionIds,
    decoration: monster.decoration,
    decorationVersion: monster.decorationVersion,
  );
}

/// Firebase・描画・OS の共有シートを呼ばずに [calls] へ呼び出しを残す [CardSharer] を返す。
/// loadArtImage は [artImage] の複製を返し ([artImage] が null なら throw する)、renderPng は 1×1 の PNG を返し、
/// shareImage は [shareResultStatus] を返す。
CardSharer fakeCardSharer({
  required RecordedShareCalls calls,
  required ui.Image? artImage,
  required ShareResultStatus shareResultStatus,
}) => CardSharer(
  loadArtImage: ({required artPath}) async {
    calls.loadedArtPaths.add(artPath);
    // 共有のボタンは使い終わった画像を dispose するため、呼ばれるたびに複製を渡す
    return artImage?.clone() ?? (throw StateError('$artPath を読めない'));
  },
  renderPng: ({required view, required card, required format}) async {
    calls.renderedCards.add((card: card, format: format));
    return _onePixelPng;
  },
  shareImage:
      ({
        required pngBytes,
        required fileName,
        required text,
        required sharePositionOrigin,
      }) async {
        calls.sharedImages.add((fileName: fileName, text: text));
        return shareResultStatus;
      },
  logEvent: ({required event, required parameters}) async =>
      calls.loggedEvents.add((event: event, parameters: parameters)),
);
