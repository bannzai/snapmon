// CPU の強さのシミュレーション (issue #267)。実機で何戦もする代わりに、バトルの計算を条件を変えて何度も繰り返し、
// 利用者の勝率・平均ラウンド数・1 ダメージの打撃の割合の表を標準出力に書く。
// 開発用の Mac では実行せず (CLAUDE.md「ビルド・テスト・検証方法」)、GitHub Actions の workflow
// `.github/workflows/battle-simulation.yml` (workflow_dispatch) で `dart run tool/simulate_battles.dart` を実行して読む。
//
// 使い方: dart run tool/simulate_battles.dart [--seeds <数>] [--damage-percents 50,70,80,90,100] [--hit-points-percents 40,50,60,70,100]
//   --seeds: 利用者 1 体 × CPU 1 体の組ごとの乱数の数 (既定 5。既定の組み合わせ 36 × 5 体 = 180 組 × 5 = 900 戦)
//   --damage-percents / --hit-points-percents: 試す CPU のダメージの割合・最大 HP の割合 (%) の一覧
// レベルの組 (利用者 / CPU) は Lv.1・4・10・20 の同レベルと、issue #267 の Lv.4 対 Lv.2、Lv.2 対 Lv.4 を試す。

import 'dart:convert';
import 'dart:io';

import 'package:snapmon/domain/battle/battle_simulation.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/sample/sample_data_path.dart';

/// 試すレベルの組 (利用者のレベル, CPU のレベル)。同レベルの 4 段階と、issue #267 のスクリーンショットの差 (Lv.4 対 Lv.2) とその逆。
const List<({int player, int opponent})> levelPairs = [
  (player: 1, opponent: 1),
  (player: 4, opponent: 4),
  (player: 10, opponent: 10),
  (player: 20, opponent: 20),
  (player: 4, opponent: 2),
  (player: 2, opponent: 4),
];

void main(List<String> arguments) {
  final seedCount = int.parse(_option(arguments, '--seeds') ?? '5');
  final damagePercents = _percents(
    _option(arguments, '--damage-percents') ?? '50,70,80,90,100',
  );
  final hitPointsPercents = _percents(
    _option(arguments, '--hit-points-percents') ?? '40,50,60,70,100',
  );
  final sampleJson =
      jsonDecode(File(sampleDataAssetPath).readAsStringSync())
          as Map<String, dynamic>;
  final master = MasterData.fromJson(
    json: sampleJson['definitions'] as Map<String, dynamic>,
  );
  final sampleDefinitions = [
    for (final monsterJson in sampleJson['monsters'] as List<dynamic>)
      MonsterDefinition.fromJson(
        json:
            (monsterJson as Map<String, dynamic>)['definition']
                as Map<String, dynamic>,
      ),
  ];
  final playerDefinitions = simulationPlayerDefinitions(
    sampleDefinitions: sampleDefinitions,
  );
  stdout.writeln(
    '| 利用者 Lv | CPU Lv | 技の選び方 | ダメージ % | 最大 HP % | 戦数 | 利用者の勝率 | 平均ラウンド | 最長ラウンド | 利用者の 1 ダメージ | CPU の 1 ダメージ |',
  );
  stdout.writeln(
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
  );
  for (final levels in levelPairs) {
    for (final policy in SimulatedPlayerPolicy.values) {
      for (final damagePercent in damagePercents) {
        for (final hitPointsPercent in hitPointsPercents) {
          final result = simulateBattles(
            master: master,
            playerDefinitions: playerDefinitions,
            opponentDefinitions: sampleDefinitions,
            condition: (
              playerLevel: levels.player,
              opponentLevel: levels.opponent,
              opponentDamagePercent: damagePercent,
              opponentHitPointsPercent: hitPointsPercent,
              playerPolicy: policy,
              seedCount: seedCount,
            ),
          );
          stdout.writeln(
            '| ${levels.player} | ${levels.opponent} | ${policy.name} | $damagePercent | $hitPointsPercent '
            '| ${result.battles} | ${_percent(result.playerWins, result.battles)} '
            '| ${(result.totalRounds / result.battles).toStringAsFixed(1)} | ${result.maximumRounds} '
            '| ${_percent(result.playerOneDamageHits, result.playerAttackHits)} '
            '| ${_percent(result.opponentOneDamageHits, result.opponentAttackHits)} |',
          );
        }
      }
    }
  }
}

/// `--名前 値` の形の引数の値。無ければ null。
String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

/// カンマ区切りの整数の一覧。
List<int> _percents(String text) => [
  for (final part in text.split(',')) int.parse(part.trim()),
];

/// [count] / [total] を小数 1 桁の % で返す。[total] が 0 なら「-」。
String _percent(int count, int total) =>
    total == 0 ? '-' : '${(count * 100 / total).toStringAsFixed(1)}%';
