import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/master/master_data.dart';
import '../domain/monster/monster_definition.dart';
import '../features/dex/owned_monster.dart';
import 'sample_data_path.dart';

export 'sample_data_path.dart';

/// 見本の対戦相手。ログインが無い時 (DEBUG ビルド) の PvP の相手の代わり (lib/features/opponent/opponent_screen.dart)。
class SampleOpponent {
  /// 見本の対戦相手を作る。
  const SampleOpponent({
    required this.id,
    required this.name,
    required this.monsterIDs,
  });

  /// JSON から見本の対戦相手を読む。
  factory SampleOpponent.fromJson({required Map<String, dynamic> json}) =>
      SampleOpponent(
        id: json['id'] as String,
        name: json['name'] as String,
        monsterIDs: [
          for (final monsterID in json['monsterIDs'] as List<dynamic>)
            monsterID as String,
        ],
      );

  /// 対戦相手の識別子。
  final String id;

  /// 画面に出す対戦相手の名前。
  final String name;

  /// 手持ちの見本のモンスターの識別子 ([SampleData.monsters] の定義の `id`)。
  final List<String> monsterIDs;
}

/// 見本データ (`assets/samples/sample_monsters.json`) の中身。
class SampleData {
  /// 見本データを作る。
  const SampleData({
    required this.definitions,
    required this.monsters,
    required this.opponents,
    required this.cpuTrainerNames,
  });

  /// JSON から見本データを読む。
  factory SampleData.fromJson({required Map<String, dynamic> json}) =>
      SampleData(
        definitions: MasterData.fromJson(
          json: json['definitions'] as Map<String, dynamic>,
        ),
        monsters: [
          for (final monsterJson in json['monsters'] as List<dynamic>)
            OwnedMonster(
              definition: MonsterDefinition.fromJson(
                json:
                    (monsterJson as Map<String, dynamic>)['definition']
                        as Map<String, dynamic>,
              ),
              level: monsterJson['level'] as int,
              actionCardMoveIDs: const [],
              artPath: monsterJson['artPath'] as String,
              definitionIDs: const [],
              decoration: null,
              decorationVersion: null,
            ),
        ],
        opponents: [
          for (final opponentJson in json['opponents'] as List<dynamic>)
            SampleOpponent.fromJson(json: opponentJson as Map<String, dynamic>),
        ],
        cpuTrainerNames: [
          for (final cpuTrainerName in json['cpuTrainerNames'] as List<dynamic>)
            cpuTrainerName as String,
        ],
      );

  /// 見本のモンスターが使う属性・技の定義。master はアプリに同梱しない (ADR 0001) ため、
  /// master (`assets/master/master.json`) から見本で使う物だけを同じ ID・同じ値で写してある
  /// (一致は test/sample/sample_data_test.dart で検査する)。
  final MasterData definitions;

  /// 見本のモンスター。
  final List<OwnedMonster> monsters;

  /// 見本の対戦相手 (ログインが無い時の他のユーザーの代わり)。
  final List<SampleOpponent> opponents;

  /// CPU トレーナー (CPU 対戦の相手) の名前。対戦の相手はこの中から乱数で選んだ名前と、見本のモンスター ([monsters]) から
  /// 乱数で選んだ手持ちで組む (lib/features/opponent/cpu_party.dart の `chooseRandomCpuOpponent`。2026-11-08 の DIRECTION.md「決めたこと」)。
  /// 名前は他のユーザーと見分けられるよう「CPU」を含める (どの画面の言語でも同じ印にするため、文言ではなく見本データに持つ)。
  final List<String> cpuTrainerNames;

  /// [monsterID] の見本のモンスターを返す。無ければ [StateError] を投げる。
  OwnedMonster monsterByID({required String monsterID}) => monsters.firstWhere(
    (monster) => monster.definition.id == monsterID,
    orElse: () => throw StateError('見本のモンスター $monsterID が無い'),
  );
}

/// [bundle] から見本データを読む。
Future<SampleData> loadSampleData({required AssetBundle bundle}) async =>
    SampleData.fromJson(
      json:
          jsonDecode(await bundle.loadString(sampleDataAssetPath))
              as Map<String, dynamic>,
    );
