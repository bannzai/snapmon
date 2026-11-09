// CPU の強さのシミュレーション (issue #267)。実機で何戦もする代わりに、バトルの計算を条件を変えて何度も繰り返し、
// 利用者の勝率・平均ラウンド数・1 ダメージの打撃の割合の表を標準出力に書く。
// 開発用の Mac では実行せず (CLAUDE.md「ビルド・テスト・検証方法」)、GitHub Actions の workflow
// `.github/workflows/battle-simulation.yml` (PR と workflow_dispatch) で `dart run tool/simulate_battles.dart` を実行して読む。
//
// 使い方: dart run tool/simulate_battles.dart [--seeds <数>] [--damage-percents <%,...>] [--hit-points-percents <%,...>]
//   --seeds: 利用者 1 体 × CPU 1 体の組ごとの乱数の数
//   --damage-percents / --hit-points-percents: 試す CPU のダメージの割合・最大 HP の割合 (%) の一覧
// 省略した時の値と、その値にした理由は下の定数。
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

/// `--seeds` を省略した時の乱数の数。利用者 36 体 × CPU 5 体 (自分と同じ見本を除く) = 180 組 × 5 で 1 条件 900 戦になり、
/// issue #240 の計測と同じ戦数で比べられるため。
const String defaultSeedCount = '5';

/// `--damage-percents` を省略した時に試す CPU のダメージの割合。issue #240 の 50 と補正なしの 100 の間を、切り捨てで 1 に潰れる
/// 境目を探すために 70・80・90 で刻んだ (issue #267 の 1 回目の計測で 70 でも潰れたため 80・90 を足した)。
const String defaultDamagePercents = '50,70,80,90,100';

/// `--hit-points-percents` を省略した時に試す CPU の最大 HP の割合。1 回目の計測で 50 が Lv.1 の目標 (勝率 60%) の手前だったため、
/// 40 から 70 を 10 ずつと補正なしの 100 にした。
const String defaultHitPointsPercents = '40,50,60,70,100';

void main(List<String> arguments) {
  final damagePercents = _percents(
    text:
        _option(arguments: arguments, name: '--damage-percents') ??
        defaultDamagePercents,
  );
  final hitPointsPercents = _percents(
    text:
        _option(arguments: arguments, name: '--hit-points-percents') ??
        defaultHitPointsPercents,
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
              seedCount: int.parse(
                _option(arguments: arguments, name: '--seeds') ??
                    defaultSeedCount,
              ),
            ),
          );
          stdout.writeln(
            '| ${levels.player} | ${levels.opponent} | ${policy.name} | $damagePercent | $hitPointsPercent '
            '| ${result.battles} | ${_percent(count: result.playerWins, total: result.battles)} '
            '| ${(result.totalRounds / result.battles).toStringAsFixed(1)} | ${result.maximumRounds} '
            '| ${_percent(count: result.playerOneDamageHits, total: result.playerAttackHits)} '
            '| ${_percent(count: result.opponentOneDamageHits, total: result.opponentAttackHits)} |',
          );
        }
      }
    }
  }
}

/// [arguments] のうち `[name] 値` の形の引数の値。無いか、値が空なら null (workflow が未指定の入力を空で渡すため)。
String? _option({required List<String> arguments, required String name}) {
  final index = arguments.indexOf(name);
  return index >= 0 &&
          index + 1 < arguments.length &&
          arguments[index + 1].isNotEmpty
      ? arguments[index + 1]
      : null;
}

/// カンマ区切りの整数の一覧 [text] を読む。
List<int> _percents({required String text}) => [
  for (final part in text.split(',')) int.parse(part.trim()),
];

/// [count] / [total] を小数 1 桁の % で返す。[total] が 0 なら「-」。
String _percent({required int count, required int total}) =>
    total == 0 ? '-' : '${(count * 100 / total).toStringAsFixed(1)}%';
