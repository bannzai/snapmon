import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/move_expression.dart';

void main() {
  // TypeScript の評価器のテスト (functions/test/unit/move_expression.test.ts) と共通のテストケース
  final fixture =
      jsonDecode(
            File('test/fixtures/move_expression_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final variables = (fixture['variables'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(name, value as int),
  );

  /// [expression] を共通のテストケースの変数で評価した値。評価できなければ 'error'。
  Object evaluateOrError({required String expression}) {
    try {
      return evaluateMoveExpression(
        node: parseMoveExpression(source: expression),
        variables: variables,
      );
    } on MoveExpressionException {
      return 'error';
    }
  }

  group('evaluateMoveExpression', () {
    for (final testCase in fixture['cases'] as List<dynamic>) {
      final expression =
          (testCase as Map<String, dynamic>)['expression'] as String;
      test('$expression → ${testCase['expected']}', () {
        expect(evaluateOrError(expression: expression), testCase['expected']);
      });
    }

    test('変数の一覧が共通のテストケースと一致する', () {
      expect(moveExpressionVariableNames, fixture['variableNames']);
      expect(variables.keys.toList(), fixture['variableNames']);
    });
  });

  test('moveExpressionViolation: 一覧の変数だけを使う式を通し、未知の変数・文法の誤りを理由付きで返す', () {
    expect(
      moveExpressionViolation(
        source: 'if(opponent.defense > self.attack, 150, 100)',
      ),
      isNull,
    );
    expect(
      moveExpressionViolation(
        source: 'if(opponent.armor > self.attack, 150, 100)',
      ),
      contains('opponent.armor'),
    );
    expect(moveExpressionViolation(source: 'if(1, 2)'), contains('引数'));
  });

  test('formatMoveExpression: 変数を日本語に、演算子を記号にし、要る所だけ括弧を付ける', () {
    expect(
      formatMoveExpression(
        source: 'if(opponent.defense > self.attack, 150, 100)',
      ),
      '相手の防御 > 自分の攻撃 なら 150、それ以外は 100',
    );
    expect(
      formatMoveExpression(
        source:
            '100 + 100 * (opponent.maximumHitPoints - opponent.hitPoints) / opponent.maximumHitPoints',
      ),
      '100 + 100 × (相手の最大 HP − 相手の HP) ÷ 相手の最大 HP',
    );
    expect(
      formatMoveExpression(source: 'if(not sharesElementType, 120, 100)'),
      '相手と同じ属性を持つ ではない なら 120、それ以外は 100',
    );
    expect(
      formatMoveExpression(
        source: 'if(movesFirst and battleDate.day == 1, 130, 100)',
      ),
      '相手より先に行動した かつ 対戦日の日 = 1 なら 130、それ以外は 100',
    );
    expect(formatMoveExpression(source: '10 - (4 - 3)'), '10 − (4 − 3)');
    expect(
      formatMoveExpression(source: 'min(3, max(1, 2))'),
      '最小(3, 最大(1, 2))',
    );
    expect(
      formatMoveExpression(source: '2 * if(movesFirst, 3, 4)'),
      '2 × (相手より先に行動した なら 3、それ以外は 4)',
    );
    expect(formatMoveExpression(source: '-(1 + 2)'), '−(1 + 2)');
    expect(formatMoveExpression(source: 'if(1,'), 'if(1,');
  });
}
