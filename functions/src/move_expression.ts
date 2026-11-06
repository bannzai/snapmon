// 技の特殊効果を master に書く式 (documents/game-rules.md「技の式」) の解析・評価。
// 同じ文法と同じ評価の規則を lib/domain/battle/move_expression.dart が持ち、2 つが同じ式・同じ入力で同じ整数を返すことを
// 共通のテストケース (test/fixtures/move_expression_cases.json) で確かめる。

/**
 * 式の値と途中の値の絶対値の上限。超えたら評価できない式として扱う。
 * 2^31 − 1 にしたのは、上限以内の 2 つの値の積が 2^62 に収まり Dart の 64bit の int で桁あふれせず、
 * JavaScript の number (double) でも上限以内の値と割り算は正確に計算でき、上限を超えたことも同じく判定できるため。
 */
export const MOVE_EXPRESSION_VALUE_LIMIT = 2147483647;

/** 式に書ける変数の名前。値は技を使う直前の状況から決める。真偽を表す変数は 1 (真) か 0 (偽)。 */
export const MOVE_EXPRESSION_VARIABLE_NAMES = [
  "self.hitPoints",
  "self.maximumHitPoints",
  "self.attack",
  "self.defense",
  "self.speed",
  "self.level",
  "opponent.hitPoints",
  "opponent.maximumHitPoints",
  "opponent.attack",
  "opponent.defense",
  "opponent.speed",
  "opponent.level",
  "move.power",
  "move.remainingPowerPoints",
  "move.maximumPowerPoints",
  "movesFirst",
  "sharesElementType",
  "battleDate.year",
  "battleDate.month",
  "battleDate.day",
] as const;

/** 式を解析・評価できない時 (文法の誤り・未知の変数・0 での割り算・上限を超える値) の例外。 */
export class MoveExpressionError extends Error {}

/** 式の構文木の節。 */
export type MoveExpressionNode =
  | { type: "literal"; value: number }
  | { type: "variable"; name: string }
  | { type: "unary"; operator: "-" | "not"; operand: MoveExpressionNode }
  | { type: "binary"; operator: string; left: MoveExpressionNode; right: MoveExpressionNode }
  | { type: "call"; functionName: "if" | "min" | "max"; arguments: MoveExpressionNode[] };

/** 比較の演算子。連鎖 (`a < b < c`) は書けない。 */
const COMPARISON_OPERATORS = new Set(["<", "<=", "==", "!=", ">=", ">"]);

/** 識別子の形。`and` `or` `not` は識別子にしない。 */
const IDENTIFIER_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$/;

/** `source` を字句に分ける。知らない文字があれば MoveExpressionError を投げる。 */
function tokenize(source: string): string[] {
  const pattern = /\s+|([0-9]+|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*|<=|>=|==|!=|[-+*/()<>,])/y;
  const tokens: string[] = [];
  let position = 0;
  while (position < source.length) {
    pattern.lastIndex = position;
    const match = pattern.exec(source);
    if (!match) {
      throw new MoveExpressionError(`使えない文字 ${source[position]} がある`);
    }
    if (match[1] !== undefined) {
      tokens.push(match[1]);
    }
    position = pattern.lastIndex;
  }
  return tokens;
}

/** `token` が識別子 (変数の名前・関数の名前) の形か。 */
function isIdentifier(token: string): boolean {
  return IDENTIFIER_PATTERN.test(token) && !["and", "or", "not"].includes(token);
}

/** `source` を式として解析した構文木を返す。文法の誤りは MoveExpressionError を投げる。 */
export function parseMoveExpression(source: string): MoveExpressionNode {
  const tokens = tokenize(source);
  let position = 0;
  /** 次に読む字句を返す (読み進めない)。式の終わりなら undefined。 */
  const peek = (): string | undefined => tokens[position];
  /** 次の字句を読み進めて返す。式の終わりなら MoveExpressionError を投げる。 */
  const next = (): string => {
    const token = peek();
    if (token === undefined) {
      throw new MoveExpressionError("式が途中で終わっている");
    }
    position++;
    return token;
  };
  /** 次の字句が `token` であることを確かめて読み進める。違えば MoveExpressionError を投げる。 */
  const expect = (token: string): void => {
    const actual = next();
    if (actual !== token) {
      throw new MoveExpressionError(`${token} が要る所に ${actual} がある`);
    }
  };

  /** 括弧・整数のリテラル・関数の呼び出し・変数のどれか 1 つを読む。 */
  const parsePrimary = (): MoveExpressionNode => {
    const token = next();
    if (token === "(") {
      const inner = parseOr();
      expect(")");
      return inner;
    }
    if (/^[0-9]+$/.test(token)) {
      // 10 桁を超えると上限を必ず超えるため、数にする前に断る (Dart と同じ判定にする)
      const value = token.length > 10 ? undefined : Number(token);
      if (value === undefined || value > MOVE_EXPRESSION_VALUE_LIMIT) {
        throw new MoveExpressionError(`リテラル ${token} が上限を超えている`);
      }
      return { type: "literal", value };
    }
    if (isIdentifier(token)) {
      if (peek() === "(") {
        next();
        const callArguments: MoveExpressionNode[] = [];
        if (peek() !== ")") {
          callArguments.push(parseOr());
          while (peek() === ",") {
            next();
            callArguments.push(parseOr());
          }
        }
        expect(")");
        if (token !== "if" && token !== "min" && token !== "max") {
          throw new MoveExpressionError(`未知の関数 ${token}`);
        }
        const arityIsValid = token === "if" ? callArguments.length === 3 : callArguments.length >= 2;
        if (!arityIsValid) {
          throw new MoveExpressionError(`${token} の引数の数が違う (${callArguments.length} 個)`);
        }
        return { type: "call", functionName: token, arguments: callArguments };
      }
      return { type: "variable", name: token };
    }
    throw new MoveExpressionError(`値が要る所に ${token} がある`);
  };

  /** 単項の `-` (連ねてよい) と、その対象を読む。 */
  const parseUnaryMinus = (): MoveExpressionNode => {
    if (peek() === "-") {
      next();
      return { type: "unary", operator: "-", operand: parseUnaryMinus() };
    }
    return parsePrimary();
  };

  /** `operators` の二項の演算子で `parseOperand` の項を左から結ぶ読み手を返す。 */
  const parseLeftAssociative = (operators: string[], parseOperand: () => MoveExpressionNode) => (): MoveExpressionNode => {
    let node = parseOperand();
    while (operators.includes(peek() ?? "")) {
      const operator = next();
      node = { type: "binary", operator, left: node, right: parseOperand() };
    }
    return node;
  };

  /** `*`・`/` で結んだ項を左から読む。 */
  const parseMultiplicative = parseLeftAssociative(["*", "/"], parseUnaryMinus);
  /** `+`・`-` で結んだ項を左から読む。 */
  const parseAdditive = parseLeftAssociative(["+", "-"], parseMultiplicative);

  /** 比較を 1 つまで読む。比較を連ねていれば MoveExpressionError を投げる。 */
  const parseComparison = (): MoveExpressionNode => {
    const left = parseAdditive();
    if (!COMPARISON_OPERATORS.has(peek() ?? "")) {
      return left;
    }
    const operator = next();
    const node: MoveExpressionNode = { type: "binary", operator, left, right: parseAdditive() };
    if (COMPARISON_OPERATORS.has(peek() ?? "")) {
      throw new MoveExpressionError("比較は連ねて書けない");
    }
    return node;
  };

  /** `not` (連ねてよい) と、その対象の比較を読む。 */
  const parseNot = (): MoveExpressionNode => {
    if (peek() === "not") {
      next();
      return { type: "unary", operator: "not", operand: parseNot() };
    }
    return parseComparison();
  };

  /** `and` で結んだ項を左から読む。 */
  const parseAnd = parseLeftAssociative(["and"], parseNot);
  /** `or` で結んだ式を読む (式の全体の読み手。括弧と引数の中から呼ぶ)。 */
  const parseOr: () => MoveExpressionNode = parseLeftAssociative(["or"], parseAnd);

  const root = parseOr();
  if (position !== tokens.length) {
    throw new MoveExpressionError(`式の後ろに ${tokens[position]} が余っている`);
  }
  return root;
}

/** `value` の絶対値が上限以内なら返し、超えていれば MoveExpressionError を投げる。 */
function checked(value: number): number {
  if (Math.abs(value) > MOVE_EXPRESSION_VALUE_LIMIT) {
    throw new MoveExpressionError(`途中の値 ${value} が上限を超えている`);
  }
  return value;
}

/**
 * `node` を `variables` (変数の名前と値) で評価した整数を返す。
 * 比較と論理の演算は真を 1、偽を 0 で返し、条件は 0 以外を真とみなす。割り算は 0 の方向へ切り捨てる。
 * `if` は選んだ枝だけを、`and`・`or` は結果が決まるまでの項だけを評価する。
 * 未知の変数・0 での割り算・絶対値が MOVE_EXPRESSION_VALUE_LIMIT を超える値は MoveExpressionError を投げる。
 */
export function evaluateMoveExpression({ node, variables }: { node: MoveExpressionNode; variables: Record<string, number> }): number {
  /** `current` の値を評価する。 */
  const evaluate = (current: MoveExpressionNode): number => {
    switch (current.type) {
      case "literal":
        return current.value;
      case "variable": {
        const value = Object.hasOwn(variables, current.name) ? variables[current.name] : undefined;
        if (value === undefined) {
          throw new MoveExpressionError(`未知の変数 ${current.name}`);
        }
        return checked(value);
      }
      case "unary":
        return current.operator === "-" ? -evaluate(current.operand) : evaluate(current.operand) === 0 ? 1 : 0;
      case "binary": {
        if (current.operator === "and") {
          return evaluate(current.left) !== 0 && evaluate(current.right) !== 0 ? 1 : 0;
        }
        if (current.operator === "or") {
          return evaluate(current.left) !== 0 || evaluate(current.right) !== 0 ? 1 : 0;
        }
        const left = evaluate(current.left);
        const right = evaluate(current.right);
        switch (current.operator) {
          case "+":
            return checked(left + right);
          case "-":
            return checked(left - right);
          case "*":
            return checked(left * right);
          case "/":
            if (right === 0) {
              throw new MoveExpressionError("0 で割っている");
            }
            return Math.trunc(left / right);
          case "<":
            return left < right ? 1 : 0;
          case "<=":
            return left <= right ? 1 : 0;
          case "==":
            return left === right ? 1 : 0;
          case "!=":
            return left !== right ? 1 : 0;
          case ">=":
            return left >= right ? 1 : 0;
          default:
            return left > right ? 1 : 0;
        }
      }
      case "call":
        if (current.functionName === "if") {
          return evaluate(current.arguments[0]) !== 0 ? evaluate(current.arguments[1]) : evaluate(current.arguments[2]);
        }
        return current.arguments.map(evaluate).reduce((left, right) => (current.functionName === "min" ? Math.min(left, right) : Math.max(left, right)));
    }
  };
  // -0 (0 の符号反転・負の数の割り算の切り捨て) を 0 にそろえる (Dart の int に -0 は無いため)
  return evaluate(node) + 0;
}

/** `node` が参照する変数の名前。 */
function variableNamesOf(node: MoveExpressionNode): string[] {
  switch (node.type) {
    case "literal":
      return [];
    case "variable":
      return [node.name];
    case "unary":
      return variableNamesOf(node.operand);
    case "binary":
      return [...variableNamesOf(node.left), ...variableNamesOf(node.right)];
    case "call":
      return node.arguments.flatMap(variableNamesOf);
  }
}

/**
 * `source` が文法どおりで、MOVE_EXPRESSION_VARIABLE_NAMES にある変数だけを使っているかを確かめる。
 * 問題が無ければ undefined、あればその理由を返す。
 */
export function moveExpressionViolation(source: string): string | undefined {
  try {
    const unknownNames = variableNamesOf(parseMoveExpression(source)).filter((name) => !(MOVE_EXPRESSION_VARIABLE_NAMES as readonly string[]).includes(name));
    return unknownNames.length === 0 ? undefined : `未知の変数 ${unknownNames.join(", ")}`;
  } catch (error) {
    if (error instanceof MoveExpressionError) {
      return error.message;
    }
    throw error;
  }
}
