import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/master/master_data.dart';
import '../domain/monster/monster_definition.dart';
import '../features/dex/owned_monster.dart';

/// 見本データのファイル。CPU 対戦の相手、ログインが無い時 (DEBUG ビルド) の PvP の相手の代わり、開発者メニューの見本の投入に使う。
const String sampleDataAssetPath = 'assets/samples/sample_monsters.json';

/// 見本の対戦相手のうち、CPU 対戦の相手 (「CPU トレーナー」) の識別子。手持ちのレベルは挑む時に自分の手持ちに合わせる。
const String cpuOpponentId = 'sample-cpu';

/// 見本の対戦相手。CPU 対戦の相手 ([cpuOpponentId]) と、ログインが無い時 (DEBUG ビルド) の PvP の相手の代わり (lib/features/opponent/opponent_screen.dart)。
class SampleOpponent {
  /// 見本の対戦相手を作る。
  const SampleOpponent({
    required this.id,
    required this.name,
    required this.monsterIds,
  });

  /// JSON から見本の対戦相手を読む。
  factory SampleOpponent.fromJson({required Map<String, dynamic> json}) =>
      SampleOpponent(
        id: json['id'] as String,
        name: json['name'] as String,
        monsterIds: [
          for (final monsterId in json['monsterIds'] as List<dynamic>)
            monsterId as String,
        ],
      );

  /// 対戦相手の識別子。
  final String id;

  /// 画面に出す対戦相手の名前。
  final String name;

  /// 手持ちの見本のモンスターの識別子 ([SampleData.monsters] の定義の `id`)。
  final List<String> monsterIds;
}

/// 見本データ (`assets/samples/sample_monsters.json`) の中身。
class SampleData {
  /// 見本データを作る。
  const SampleData({
    required this.definitions,
    required this.monsters,
    required this.opponents,
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
              artPath: monsterJson['artPath'] as String,
              definitionIds: const [],
            ),
        ],
        opponents: [
          for (final opponentJson in json['opponents'] as List<dynamic>)
            SampleOpponent.fromJson(json: opponentJson as Map<String, dynamic>),
        ],
      );

  /// 見本のモンスターが使う属性・技の定義。master はアプリに同梱しない (ADR 0001) ため、
  /// master (`assets/master/master.json`) から見本で使う物だけを同じ ID・同じ値で写してある
  /// (一致は test/sample/sample_data_test.dart で検査する)。
  final MasterData definitions;

  /// 見本のモンスター。
  final List<OwnedMonster> monsters;

  /// 見本の対戦相手。
  final List<SampleOpponent> opponents;

  /// [monsterId] の見本のモンスターを返す。無ければ [StateError] を投げる。
  OwnedMonster monsterById({required String monsterId}) => monsters.firstWhere(
    (monster) => monster.definition.id == monsterId,
    orElse: () => throw StateError('見本のモンスター $monsterId が無い'),
  );
}

/// [bundle] から見本データを読む。
Future<SampleData> loadSampleData({required AssetBundle bundle}) async =>
    SampleData.fromJson(
      json:
          jsonDecode(await bundle.loadString(sampleDataAssetPath))
              as Map<String, dynamic>,
    );
