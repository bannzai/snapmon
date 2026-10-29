import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../domain/master/master_data.dart';
import '../../domain/random/deterministic_random.dart';
import '../../sample/sample_data.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../opponent/battle_definitions.dart';
import '../opponent/cpu_party.dart';
import '../opponent/pvp_client.dart';
import '../opponent/pvp_opponent.dart';

/// 初回の導線 (手持ちが空の時に写真を選んでそのまま戦う 1 戦目) の対戦相手と、その対戦に使う定義。
/// `pvpOpponent` は相手が他のユーザーの時の候補そのもの (バトルの画面の通報・ブロックの宛先)。CPU トレーナーの時は null。
typedef FirstBattleOpponent = ({
  String opponentName,
  List<OwnedMonster> opponentParty,
  BattleOpponentKind opponentKind,
  PvpOpponent? pvpOpponent,
  MasterData definitions,
});

/// 切り出した画像を読む関数 (CardSharer.loadArtImage と同じ形)。
typedef LoadArtImage = Future<ui.Image> Function({required String artPath});

/// 他のユーザーの候補の先頭と戦わせてよい、同じ絵ではない候補の数。これに満たない時は CPU トレーナーを混ぜて選ぶ
/// (候補が 1 人だけだと毎回その 1 人になるため。issue #105 の「候補が 1 人以下の時は混ぜる」)。
const int _firstBattleCandidateCountWithoutCpu = 2;

/// 生まれたモンスターを手持ちに入れた後の [dexStore] の手持ちと戦う、初回のバトルの相手を決める。
/// 他のユーザーの候補 ([PvpClient.fetchOpponents]。手持ちの平均レベルが近い順) から自分の手持ちと同じ絵のモンスターを持つ候補を除き
/// ([excludeOpponentsWithSameArt]。絵は [loadArtImage] で読む)、残りと CPU トレーナー ([excludeCpuTrainersWithSameArt]) から
/// [chooseFirstBattleOpponent] で選ぶ。
/// 候補を取れない時 (ログインが無い・呼び出しの失敗) は候補 0 人として扱う。CPU トレーナーの手持ちのレベルは
/// [randomSeed] で自分の手持ちに合わせる ([buildCpuParty])。選んだ候補の相手の定義を読めない時も CPU トレーナーにする。
/// 図鑑の定義を読み直せない時は例外を投げる ([prepareBattleDefinitions])。
Future<FirstBattleOpponent> prepareFirstBattleOpponent({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required int randomSeed,
  required LoadArtImage loadArtImage,
}) async {
  var pvpOpponents = const <PvpOpponent>[];
  try {
    pvpOpponents = await pvpClient.fetchOpponents() ?? const [];
  } catch (_) {
    // 初回の 1 戦は他のユーザーを読めなくても止めず、CPU トレーナーと戦わせる (issue #45 の「取れない時は CPU」)
  }
  final choice = chooseFirstBattleOpponent(
    candidates: await excludeOpponentsWithSameArt(
      pvpOpponents: pvpOpponents,
      playerParty: dexStore.party,
      loadArtImage: loadArtImage,
    ),
    cpuTrainers: excludeCpuTrainersWithSameArt(
      sampleData: sampleData,
      playerParty: dexStore.party,
    ),
    randomSeed: randomSeed,
  );
  final pvpOpponent = choice.pvpOpponent;
  if (pvpOpponent != null) {
    try {
      return (
        opponentName: pvpOpponent.displayName,
        opponentParty: pvpOpponent.monsters,
        opponentKind: BattleOpponentKind.pvp,
        pvpOpponent: pvpOpponent,
        definitions: await prepareBattleDefinitions(
          dexStore: dexStore,
          pvpClient: pvpClient,
          pvpOpponentMonsters: pvpOpponent.monsters,
        ),
      );
    } catch (_) {
      // 選んだ候補は「もう一度試す」でも同じ相手になり得るため、その相手の定義を読めない時は止めずに CPU トレーナーと戦わせる。
      // 図鑑の定義を読み直せないのが原因なら、下の CPU トレーナーの準備でも同じく例外になる
    }
  }
  final cpuTrainer = choice.cpuTrainer;
  return (
    opponentName: cpuTrainer.opponent.name,
    opponentParty: buildCpuParty(
      monsters: [
        for (final monsterId in cpuTrainer.opponent.monsterIds)
          sampleData.monsterById(monsterId: monsterId),
      ],
      playerParty: dexStore.party,
      levelOffset: cpuTrainer.levelOffset,
      randomSeed: randomSeed,
    ),
    opponentKind: BattleOpponentKind.cpu,
    pvpOpponent: null,
    definitions: await prepareBattleDefinitions(
      dexStore: dexStore,
      pvpClient: pvpClient,
      pvpOpponentMonsters: null,
    ),
  );
}

/// [sampleData] の CPU トレーナーから、[playerParty] のどれかと同じ絵 (同じ画像のパス) の見本のモンスターを持つトレーナーを除いて返す。
/// 自分の手持ちに見本のモンスターがいるのは DEBUG ビルドの見本の生成・投入の時で、それ以外の手持ちの絵は Storage にあり見本と重ならない。
/// 全員が除かれる時は全員を返す (相手がいないよりは同じ絵の方がよいため)。
List<SampleCpuTrainer> excludeCpuTrainersWithSameArt({
  required SampleData sampleData,
  required List<OwnedMonster> playerParty,
}) {
  final playerArtPaths = {for (final monster in playerParty) ?monster.artPath};
  final cpuTrainers = [
    for (final cpuTrainer in sampleData.cpuTrainers)
      if (!cpuTrainer.opponent.monsterIds.any(
        (monsterId) => playerArtPaths.contains(
          sampleData.monsterById(monsterId: monsterId).artPath,
        ),
      ))
        cpuTrainer,
  ];
  return cpuTrainers.isEmpty ? sampleData.cpuTrainers : cpuTrainers;
}

/// 初回のバトルの相手を [candidates] (同じ絵の候補を除いた他のユーザー。平均レベルが近い順) と [cpuTrainers] (1 人以上) から選ぶ。
/// 候補が [_firstBattleCandidateCountWithoutCpu] 人以上なら先頭の候補、それより少なければ候補と CPU トレーナーを合わせた中から
/// [randomSeed] で 1 人を選ぶ。`pvpOpponent` が null なら `cpuTrainer` と戦う。`cpuTrainer` は候補を選んだ時も、
/// その候補の定義を読めなかった時の代わりとして [randomSeed] で決めて返す。同じ引数からは同じ相手になる。
({PvpOpponent? pvpOpponent, SampleCpuTrainer cpuTrainer})
chooseFirstBattleOpponent({
  required List<PvpOpponent> candidates,
  required List<SampleCpuTrainer> cpuTrainers,
  required int randomSeed,
}) {
  final random = DeterministicRandom(seed: randomSeed);
  final index = random.nextIntInRange(
    minimum: 0,
    maximum: candidates.length + cpuTrainers.length - 1,
  );
  if (candidates.length >= _firstBattleCandidateCountWithoutCpu) {
    return (
      pvpOpponent: candidates.first,
      cpuTrainer: cpuTrainers[index % cpuTrainers.length],
    );
  }
  return index < candidates.length
      ? (
          pvpOpponent: candidates[index],
          cpuTrainer:
              cpuTrainers[random.nextIntInRange(
                minimum: 0,
                maximum: cpuTrainers.length - 1,
              )],
        )
      : (pvpOpponent: null, cpuTrainer: cpuTrainers[index - candidates.length]);
}

/// [pvpOpponents] (平均レベルが近い順) から、[playerParty] のどれかと同じ絵のモンスターを持つ候補を除いて、先頭から
/// [_firstBattleCandidateCountWithoutCpu] 人までを順のまま返す ([chooseFirstBattleOpponent] はそれ以上を見ないため、残りの絵は読まない)。
/// 同じ絵は、画像のパスが同じか、[loadArtImage] で読んだ画素が同じもの (別のアカウントで同じ写真から生まれたモンスターは
/// Storage のパスが違うため画素で比べる)。読めない画像は比べられないため、同じ絵とは見なさない (他のユーザーを根拠なく外さないため)。
Future<List<PvpOpponent>> excludeOpponentsWithSameArt({
  required List<PvpOpponent> pvpOpponents,
  required List<OwnedMonster> playerParty,
  required LoadArtImage loadArtImage,
}) async {
  if (pvpOpponents.isEmpty) {
    return const [];
  }
  final playerArtPaths = {for (final monster in playerParty) ?monster.artPath};
  final playerArtImages = [
    for (final artPath in playerArtPaths)
      ?await _tryLoadArtImage(artPath: artPath, loadArtImage: loadArtImage),
  ];
  try {
    final candidates = <PvpOpponent>[];
    for (final pvpOpponent in pvpOpponents) {
      if (candidates.length >= _firstBattleCandidateCountWithoutCpu) {
        break;
      }
      if (!await _hasSameArt(
        monsters: pvpOpponent.monsters,
        playerArtPaths: playerArtPaths,
        playerArtImages: playerArtImages,
        loadArtImage: loadArtImage,
      )) {
        candidates.add(pvpOpponent);
      }
    }
    return candidates;
  } finally {
    for (final image in playerArtImages) {
      image.dispose();
    }
  }
}

/// [monsters] のどれかが、[playerArtPaths] と同じパスか [playerArtImages] と同じ画素の絵を持つか。
Future<bool> _hasSameArt({
  required List<OwnedMonster> monsters,
  required Set<String> playerArtPaths,
  required List<ui.Image> playerArtImages,
  required LoadArtImage loadArtImage,
}) async {
  for (final monster in monsters) {
    final artPath = monster.artPath;
    if (artPath == null) {
      continue;
    }
    if (playerArtPaths.contains(artPath)) {
      return true;
    }
    if (playerArtImages.isEmpty) {
      continue;
    }
    final image = await _tryLoadArtImage(
      artPath: artPath,
      loadArtImage: loadArtImage,
    );
    if (image == null) {
      continue;
    }
    try {
      for (final playerArtImage in playerArtImages) {
        if (await _hasSamePixels(image: image, otherImage: playerArtImage)) {
          return true;
        }
      }
    } finally {
      image.dispose();
    }
  }
  return false;
}

/// [image] と [otherImage] の大きさと RGBA の画素がすべて同じか。画素を読めない時は同じと見なさない。
Future<bool> _hasSamePixels({
  required ui.Image image,
  required ui.Image otherImage,
}) async {
  if (image.width != otherImage.width || image.height != otherImage.height) {
    return false;
  }
  try {
    final byteData = await image.toByteData();
    final otherByteData = await otherImage.toByteData();
    return byteData != null &&
        otherByteData != null &&
        listEquals(
          byteData.buffer.asUint8List(),
          otherByteData.buffer.asUint8List(),
        );
  } catch (_) {
    // 画素を読めない画像は比べず、同じ絵とは見なさない (excludeOpponentsWithSameArt の document コメント)
    return false;
  }
}

/// [artPath] の画像を [loadArtImage] で読む。読めない時は null (読めない画像は比べず、同じ絵とは見なさない。
/// [excludeOpponentsWithSameArt] の document コメント)。返した画像は呼び出し元が dispose する。
Future<ui.Image?> _tryLoadArtImage({
  required String artPath,
  required LoadArtImage loadArtImage,
}) async {
  try {
    return await loadArtImage(artPath: artPath);
  } catch (_) {
    return null;
  }
}
