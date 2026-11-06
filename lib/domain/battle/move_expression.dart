/// 技の特殊効果を master に書く式 (documents/game-rules.md「技の式」) の解析・評価・表示。
/// 同じ文法と同じ評価の規則を functions/src/move_expression.ts が持ち、2 つが同じ式・同じ入力で同じ整数を返すことを
/// 共通のテストケース (test/fixtures/move_expression_cases.json) で確かめる。
library;

/// 式の値と途中の値の絶対値の上限。超えたら評価できない式として扱う。
/// 2^31 − 1 にしたのは、上限以内の 2 つの値の積が 2^62 に収まり、iOS / Android の 64bit の int で桁あふれせず、
/// Web (JavaScript の double) でも上限を超えたことを同じく判定できるため (端末とサーバーで結果を揃える)。
const moveExpressionValueLimit = 2147483647;

/// 式に書ける変数の名前。値は技を使う直前の状況から決める (lib/domain/battle/move_special_effect.dart の
/// `calculateMoveSpecialEffect`)。真偽を表す変数は 1 (真) か 0 (偽)。
const moveExpressionVariableNames = [
  'self.hitPoints',
  'self.maximumHitPoints',
  'self.attack',
  'self.defense',
  'self.speed',
  'self.level',
  'opponent.hitPoints',
  'opponent.maximumHitPoints',
  'opponent.attack',
  'opponent.defense',
  'opponent.speed',
  'opponent.level',
  'move.power',
  'move.remainingPowerPoints',
  'move.maximumPowerPoints',
  'movesFirst',
  'sharesElementType',
  'battleDate.year',
  'battleDate.month',
  'battleDate.day',
];

/// 式を解析・評価できない時 (文法の誤り・未知の変数・0 での割り算・上限を超える値) の例外。
class MoveExpressionException implements Exception {
  /// [message] の理由で評価できなかったことを表す例外を作る。
  const MoveExpressionException({required this.message});

  /// 評価できなかった理由。
  final String message;

  @override
  String toString() => 'MoveExpressionException: $message';
}

/// 式の構文木の節。
sealed class MoveExpressionNode {
  const MoveExpressionNode();
}

/// 整数のリテラル。
class MoveExpressionLiteral extends MoveExpressionNode {
  const MoveExpressionLiteral({required this.value});

  /// リテラルの値。
  final int value;
}

/// 変数の参照。
class MoveExpressionVariable extends MoveExpressionNode {
  const MoveExpressionVariable({required this.name});

  /// 変数の名前 ([moveExpressionVariableNames] のどれか。解析では照合しない)。
  final String name;
}

/// 単項の演算 (`-` と `not`)。
class MoveExpressionUnary extends MoveExpressionNode {
  const MoveExpressionUnary({required this.operator, required this.operand});

  /// 演算子 (`-` か `not`)。
  final String operator;

  /// 演算の対象。
  final MoveExpressionNode operand;
}

/// 二項の演算 (四則演算・比較・`and`・`or`)。
class MoveExpressionBinary extends MoveExpressionNode {
  const MoveExpressionBinary({
    required this.operator,
    required this.left,
    required this.right,
  });

  /// 演算子 (`+` `-` `*` `/` `<` `<=` `==` `!=` `>=` `>` `and` `or`)。
  final String operator;

  /// 左の項。
  final MoveExpressionNode left;

  /// 右の項。
  final MoveExpressionNode right;
}

/// 関数の呼び出し (`if` `min` `max`)。
class MoveExpressionCall extends MoveExpressionNode {
  const MoveExpressionCall({
    required this.functionName,
    required this.arguments,
  });

  /// 関数の名前。
  final String functionName;

  /// 引数。`if` は (条件, 真の時の値, 偽の時の値) の 3 つ、`min`・`max` は 2 つ以上。
  final List<MoveExpressionNode> arguments;
}

/// 比較の演算子。連鎖 (`a < b < c`) は書けない。
const _comparisonOperators = {'<', '<=', '==', '!=', '>=', '>'};

/// [source] を式として解析した構文木を返す。文法の誤りは [MoveExpressionException] を投げる。
MoveExpressionNode parseMoveExpression({required String source}) {
  final tokens = _tokenize(source: source);
  var position = 0;

  /// 次に読む字句を返す (読み進めない)。式の終わりなら null。
  String? peek() => position < tokens.length ? tokens[position] : null;

  /// 次の字句を読み進めて返す。式の終わりなら [MoveExpressionException] を投げる。
  String next() {
    final token = peek();
    if (token == null) {
      throw const MoveExpressionException(message: '式が途中で終わっている');
    }
    position++;
    return token;
  }

  /// 次の字句が [token] であることを確かめて読み進める。違えば [MoveExpressionException] を投げる。
  void expect({required String token}) {
    final actual = next();
    if (actual != token) {
      throw MoveExpressionException(message: '$token が要る所に $actual がある');
    }
  }

  /// `or` で結んだ式を読む (式の全体の読み手。括弧と引数の中から呼ぶため先に宣言する)。
  late MoveExpressionNode Function() parseOr;

  /// 括弧・整数のリテラル・関数の呼び出し・変数のどれか 1 つを読む。
  MoveExpressionNode parsePrimary() {
    final token = next();
    if (token == '(') {
      final inner = parseOr();
      expect(token: ')');
      return inner;
    }
    if (RegExp(r'^[0-9]+$').hasMatch(token)) {
      // 10 桁を超えると上限を必ず超え、端末によって int.parse の振る舞いが違うため、parse の前に断る
      final value = token.length > 10 ? null : int.parse(token);
      if (value == null || value > moveExpressionValueLimit) {
        throw MoveExpressionException(message: 'リテラル $token が上限を超えている');
      }
      return MoveExpressionLiteral(value: value);
    }
    if (_isIdentifier(token: token)) {
      if (peek() == '(') {
        next();
        final arguments = <MoveExpressionNode>[];
        if (peek() != ')') {
          arguments.add(parseOr());
          while (peek() == ',') {
            next();
            arguments.add(parseOr());
          }
        }
        expect(token: ')');
        final arityIsValid = switch (token) {
          'if' => arguments.length == 3,
          'min' || 'max' => arguments.length >= 2,
          _ => throw MoveExpressionException(message: '未知の関数 $token'),
        };
        if (!arityIsValid) {
          throw MoveExpressionException(
            message: '$token の引数の数が違う (${arguments.length} 個)',
          );
        }
        return MoveExpressionCall(functionName: token, arguments: arguments);
      }
      return MoveExpressionVariable(name: token);
    }
    throw MoveExpressionException(message: '値が要る所に $token がある');
  }

  /// 単項の `-` (連ねてよい) と、その対象を読む。
  MoveExpressionNode parseUnaryMinus() {
    if (peek() == '-') {
      next();
      return MoveExpressionUnary(operator: '-', operand: parseUnaryMinus());
    }
    return parsePrimary();
  }

  /// `*`・`/` で結んだ項を左から読む。
  MoveExpressionNode parseMultiplicative() {
    var node = parseUnaryMinus();
    while (peek() == '*' || peek() == '/') {
      final operator = next();
      node = MoveExpressionBinary(
        operator: operator,
        left: node,
        right: parseUnaryMinus(),
      );
    }
    return node;
  }

  /// `+`・`-` で結んだ項を左から読む。
  MoveExpressionNode parseAdditive() {
    var node = parseMultiplicative();
    while (peek() == '+' || peek() == '-') {
      final operator = next();
      node = MoveExpressionBinary(
        operator: operator,
        left: node,
        right: parseMultiplicative(),
      );
    }
    return node;
  }

  /// 比較を 1 つまで読む。比較を連ねていれば [MoveExpressionException] を投げる。
  MoveExpressionNode parseComparison() {
    final left = parseAdditive();
    if (!_comparisonOperators.contains(peek())) {
      return left;
    }
    final operator = next();
    final node = MoveExpressionBinary(
      operator: operator,
      left: left,
      right: parseAdditive(),
    );
    if (_comparisonOperators.contains(peek())) {
      throw const MoveExpressionException(message: '比較は連ねて書けない');
    }
    return node;
  }

  /// `not` (連ねてよい) と、その対象の比較を読む。
  MoveExpressionNode parseNot() {
    if (peek() == 'not') {
      next();
      return MoveExpressionUnary(operator: 'not', operand: parseNot());
    }
    return parseComparison();
  }

  /// `and` で結んだ項を左から読む。
  MoveExpressionNode parseAnd() {
    var node = parseNot();
    while (peek() == 'and') {
      next();
      node = MoveExpressionBinary(
        operator: 'and',
        left: node,
        right: parseNot(),
      );
    }
    return node;
  }

  parseOr = () {
    var node = parseAnd();
    while (peek() == 'or') {
      next();
      node = MoveExpressionBinary(
        operator: 'or',
        left: node,
        right: parseAnd(),
      );
    }
    return node;
  };

  final root = parseOr();
  if (position != tokens.length) {
    throw MoveExpressionException(message: '式の後ろに ${tokens[position]} が余っている');
  }
  return root;
}

/// [token] が識別子 (変数の名前・関数の名前) の形か。`and` `or` `not` は識別子にしない。
bool _isIdentifier({required String token}) =>
    RegExp(
      r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
    ).hasMatch(token) &&
    !{'and', 'or', 'not'}.contains(token);

/// [source] を字句に分ける。知らない文字があれば [MoveExpressionException] を投げる。
List<String> _tokenize({required String source}) {
  final pattern = RegExp(
    r'\s+|([0-9]+|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*|<=|>=|==|!=|[-+*/()<>,])',
  );
  final tokens = <String>[];
  var position = 0;
  while (position < source.length) {
    final match = pattern.matchAsPrefix(source, position);
    if (match == null) {
      throw MoveExpressionException(message: '使えない文字 ${source[position]} がある');
    }
    if (match.group(1) case final token?) {
      tokens.add(token);
    }
    position = match.end;
  }
  return tokens;
}

/// [node] を [variables] (変数の名前と値) で評価した整数を返す。
/// 比較と論理の演算は真を 1、偽を 0 で返し、条件は 0 以外を真とみなす。割り算は 0 の方向へ切り捨てる。
/// `if` は選んだ枝だけを、`and`・`or` は結果が決まるまでの項だけを評価する。
/// 未知の変数・0 での割り算・絶対値が [moveExpressionValueLimit] を超える値は [MoveExpressionException] を投げる。
int evaluateMoveExpression({
  required MoveExpressionNode node,
  required Map<String, int> variables,
}) {
  /// [value] の絶対値が上限以内なら返し、超えていれば [MoveExpressionException] を投げる。
  int checked({required int value}) {
    if (value.abs() > moveExpressionValueLimit) {
      throw MoveExpressionException(message: '途中の値 $value が上限を超えている');
    }
    return value;
  }

  /// [node] の値を評価する。
  int evaluate(MoveExpressionNode node) => switch (node) {
    MoveExpressionLiteral(:final value) => value,
    MoveExpressionVariable(:final name) => checked(
      value:
          variables[name] ??
          (throw MoveExpressionException(message: '未知の変数 $name')),
    ),
    MoveExpressionUnary(operator: '-', :final operand) => -evaluate(operand),
    MoveExpressionUnary(:final operand) => evaluate(operand) == 0 ? 1 : 0,
    MoveExpressionBinary(operator: 'and', :final left, :final right) =>
      evaluate(left) != 0 && evaluate(right) != 0 ? 1 : 0,
    MoveExpressionBinary(operator: 'or', :final left, :final right) =>
      evaluate(left) != 0 || evaluate(right) != 0 ? 1 : 0,
    MoveExpressionBinary(:final operator, :final left, :final right) =>
      _evaluateBinary(
        operator: operator,
        left: evaluate(left),
        right: evaluate(right),
        checked: checked,
      ),
    MoveExpressionCall(functionName: 'if', :final arguments) =>
      evaluate(arguments[0]) != 0
          ? evaluate(arguments[1])
          : evaluate(arguments[2]),
    MoveExpressionCall(functionName: 'min', :final arguments) =>
      arguments
          .map(evaluate)
          .reduce((left, right) => left < right ? left : right),
    MoveExpressionCall(:final arguments) =>
      arguments
          .map(evaluate)
          .reduce((left, right) => left > right ? left : right),
  };

  return evaluate(node);
}

/// 値を評価した後の二項の演算 [operator] を [left]・[right] に当てはめる。結果は [checked] で上限を確かめる。
int _evaluateBinary({
  required String operator,
  required int left,
  required int right,
  required int Function({required int value}) checked,
}) => switch (operator) {
  '+' => checked(value: left + right),
  '-' => checked(value: left - right),
  '*' => checked(value: left * right),
  '/' =>
    right == 0
        ? throw const MoveExpressionException(message: '0 で割っている')
        : left ~/ right,
  '<' => left < right ? 1 : 0,
  '<=' => left <= right ? 1 : 0,
  '==' => left == right ? 1 : 0,
  '!=' => left != right ? 1 : 0,
  '>=' => left >= right ? 1 : 0,
  _ => left > right ? 1 : 0,
};

/// [source] が文法どおりで、[moveExpressionVariableNames] にある変数だけを使っているかを確かめる。
/// 問題が無ければ null、あればその理由を返す。
String? moveExpressionViolation({required String source}) {
  try {
    final unknownNames = _variableNamesOf(
      node: parseMoveExpression(source: source),
    ).where((name) => !moveExpressionVariableNames.contains(name));
    return unknownNames.isEmpty ? null : '未知の変数 ${unknownNames.join(', ')}';
  } on MoveExpressionException catch (error) {
    return error.message;
  }
}

/// [node] が参照する変数の名前。
Iterable<String> _variableNamesOf({required MoveExpressionNode node}) =>
    switch (node) {
      MoveExpressionLiteral() => const [],
      MoveExpressionVariable(:final name) => [name],
      MoveExpressionUnary(:final operand) => _variableNamesOf(node: operand),
      MoveExpressionBinary(:final left, :final right) => [
        ..._variableNamesOf(node: left),
        ..._variableNamesOf(node: right),
      ],
      MoveExpressionCall(:final arguments) => [
        for (final argument in arguments) ..._variableNamesOf(node: argument),
      ],
    };

/// 技の詳細の画面に出す、変数の名前の日本語の言い方。説明文は master の定義に付く文言と同じく ARB には移さない。
const _variableLabels = {
  'self.hitPoints': '自分の HP',
  'self.maximumHitPoints': '自分の最大 HP',
  'self.attack': '自分の攻撃',
  'self.defense': '自分の防御',
  'self.speed': '自分の素早さ',
  'self.level': '自分のレベル',
  'opponent.hitPoints': '相手の HP',
  'opponent.maximumHitPoints': '相手の最大 HP',
  'opponent.attack': '相手の攻撃',
  'opponent.defense': '相手の防御',
  'opponent.speed': '相手の素早さ',
  'opponent.level': '相手のレベル',
  'move.power': '技の威力',
  'move.remainingPowerPoints': '使う前の残り PP',
  'move.maximumPowerPoints': '最大 PP',
  'movesFirst': '相手より先に行動した',
  'sharesElementType': '相手と同じ属性を持つ',
  'battleDate.year': '対戦日の年',
  'battleDate.month': '対戦日の月',
  'battleDate.day': '対戦日の日',
};

/// 二項の演算子の結合の強さ (大きいほど強い) と、画面に出す記号。
const _binaryOperatorDisplay = {
  'or': (precedence: 1, text: 'または'),
  'and': (precedence: 2, text: 'かつ'),
  '<': (precedence: 4, text: '<'),
  '<=': (precedence: 4, text: '≤'),
  '==': (precedence: 4, text: '='),
  '!=': (precedence: 4, text: '≠'),
  '>=': (precedence: 4, text: '≥'),
  '>': (precedence: 4, text: '>'),
  '+': (precedence: 5, text: '+'),
  '-': (precedence: 5, text: '−'),
  '*': (precedence: 6, text: '×'),
  '/': (precedence: 6, text: '÷'),
};

/// [source] の式を、技の詳細の画面に出す日本語の文言にする (変数を日本語の言い方に、演算子を記号に置き換える)。
/// 解析できない式はそのまま返す。
String formatMoveExpression({required String source}) {
  try {
    return _formatNode(
      node: parseMoveExpression(source: source),
      precedence: 0,
    );
  } on MoveExpressionException {
    return source;
  }
}

/// [node] を文言にする。[precedence] は外側の演算の結合の強さで、[node] の方が弱ければ括弧で囲む。
String _formatNode({
  required MoveExpressionNode node,
  required int precedence,
}) {
  /// [text] の演算の強さ [ownPrecedence] が外側より弱ければ括弧で囲む。
  String wrap({required String text, required int ownPrecedence}) =>
      ownPrecedence < precedence ? '($text)' : text;
  return switch (node) {
    MoveExpressionLiteral(:final value) => '$value',
    MoveExpressionVariable(:final name) => _variableLabels[name] ?? name,
    MoveExpressionUnary(operator: '-', :final operand) =>
      '−${_formatNode(node: operand, precedence: 7)}',
    MoveExpressionUnary(:final operand) => wrap(
      text: '${_formatNode(node: operand, precedence: 4)} ではない',
      ownPrecedence: 3,
    ),
    MoveExpressionBinary(:final operator, :final left, :final right) => () {
      final display = _binaryOperatorDisplay[operator]!;
      // 左結合のため、右の項は同じ強さでも括弧が要る (a − (b − c) を a − b − c と書かない)
      return wrap(
        text:
            '${_formatNode(node: left, precedence: display.precedence)} ${display.text} ${_formatNode(node: right, precedence: display.precedence + 1)}',
        ownPrecedence: display.precedence,
      );
    }(),
    MoveExpressionCall(functionName: 'if', :final arguments) => wrap(
      text:
          '${_formatNode(node: arguments[0], precedence: 1)} なら ${_formatNode(node: arguments[1], precedence: 1)}、それ以外は ${_formatNode(node: arguments[2], precedence: 1)}',
      ownPrecedence: 0,
    ),
    MoveExpressionCall(:final functionName, :final arguments) =>
      '${functionName == 'min' ? '最小' : '最大'}(${arguments.map((argument) => _formatNode(node: argument, precedence: 0)).join(', ')})',
  };
}
