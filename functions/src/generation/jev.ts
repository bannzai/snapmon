// Jev (TypeSafe の判定 API) への問いの組み立てと呼び出し。
// API: https://docs.typesafe.ai/api.md (`POST /v1/systemone`、問いの型は noul・choice・score)。
// 問いの設計規約は ~/.claude/skills/jev/references/jev-question-design.md (二値の判定を肯定・否定の対で問う等)。
// 閾値は documents/game-rules.md「Jev の閾値」に実測とともに書き、問いの文言を変えたら測り直す (functions/scripts/calibrate-jev.mjs)。

import type { MasterElementType, MasterMove, MasterStatGrade, MasterSubjectCategory } from "./master";
import { STAT_KINDS } from "./monster_stats";
import type { SubjectDescription } from "./prompts/describe_subject";

const JEV_ENDPOINT = "https://api.typesafe.ai/v1/systemone";

/**
 * 使う Jev のモデル。`jev-latest` は版が予告なく変わり、閾値の実測が無効になるため版を固定する。
 * 版を上げる時は閾値を測り直す (2026-10-22 に `jev-1.13.0` が受け付けられることを確認した)。
 */
export const JEV_MODEL = "jev-1.13.0";

/**
 * Jev の応答を待つ時間 (ミリ秒)。1 リクエスト 0.6 秒前後の実測 (~/.claude/skills/jev/SKILL.md) に、
 * 同じ被写体の判定で問いが 40 件になる時の余裕を見た値。超えたら判定待ち (pending_judge) にする。
 */
const JEV_TIMEOUT_MILLISECONDS = 20_000;

/** 同じ被写体の判定で 1 リクエストに入れる候補の数 (ADR 0001「同じ被写体の判定」の 20 件)。 */
export const DEDUPE_CHUNK_SIZE = 20;

/** Jev の問い 1 つ。 */
export type JevQuestion =
  | { type: "noul"; instructions: unknown; criteria?: { true: string; false: string } }
  | { type: "choice"; instructions: unknown; criteria: Record<string, string> }
  | { type: "score"; instructions: unknown; criteria: string[] };

/** Jev へのリクエスト。 */
export interface JevRequest {
  /** モデル名。 */
  model: string;
  /** すべての問いが参照する内容。 */
  state: unknown;
  /** 問いの名前と問い。 */
  questions: Record<string, JevQuestion>;
}

/** Jev の答え 1 つ。 */
export type JevAnswer =
  | { type: "noul"; noul: number }
  | { type: "choice"; choice: string; confidence: number; probabilities: Record<string, number> }
  | { type: "score"; score: number; confidence: number; probabilities: Record<string, number> };

/** Jev の応答。 */
export interface JevResponse {
  /** 答えたモデル。 */
  model: string;
  /** 問いの名前ごとの答え。 */
  answers: Record<string, JevAnswer>;
  /** 使ったトークン数 (課金は入力トークンだけ)。 */
  usage: { input_tokens: number; output_tokens: number };
}

/** Jev が答えなかったこと (通信エラー・タイムアウト・HTTP エラー) を表す。生成は判定待ち (pending_judge) にして再試行に回す。 */
export class JevUnavailableError extends Error {}

/** Jev を呼ぶ関数。テストではモックに差し替える。 */
export type AskJev = (request: JevRequest) => Promise<JevResponse>;

/**
 * Jev を呼ぶ関数を作る。答えが返らない時は `JevUnavailableError` を throw する。
 * 422 (リクエストの形の誤り) は再試行しても直らないため、`JevUnavailableError` ではない Error にする。
 */
export function createAskJev({ apiKey, fetchFunction }: { apiKey: string; fetchFunction: typeof fetch }): AskJev {
  return async (request) => {
    let response: Response;
    try {
      response = await fetchFunction(JEV_ENDPOINT, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(request),
        signal: AbortSignal.timeout(JEV_TIMEOUT_MILLISECONDS),
      });
    } catch (error) {
      throw new JevUnavailableError(`Jev に接続できませんでした: ${String(error)}`);
    }
    if (response.status === 422) {
      throw new Error(`Jev がリクエストの形を受け付けませんでした: ${await response.text()}`);
    }
    if (!response.ok) {
      throw new JevUnavailableError(`Jev が HTTP ${response.status} を返しました`);
    }
    return (await response.json()) as JevResponse;
  };
}

/** 被写体の説明を、Jev の state に入れる形にする。 */
function subjectState(description: SubjectDescription): unknown {
  return { subject: description };
}

/** 物の分類を決める問い (Choice)。state には Cloud Vision のラベルも入れる (ADR 0001「同じ被写体の判定」)。 */
export function buildClassifyRequest({
  description,
  visionLabels,
  subjectCategories,
}: {
  description: SubjectDescription;
  visionLabels: string[];
  subjectCategories: MasterSubjectCategory[];
}): JevRequest {
  return {
    model: JEV_MODEL,
    state: { subject: description, imageLabels: visionLabels },
    questions: {
      category: {
        type: "choice",
        instructions: "state の subject (写真の被写体の説明) と imageLabels (同じ写真に付いたラベル) が表す物は、どの分類に入るか。",
        criteria: Object.fromEntries(subjectCategories.map((category) => [category.id, `${category.displayName}: ${category.description}`])),
      },
    },
  };
}

/** Choice の確率の高い順に分類 ID を上位 `count` 件返す。 */
export function topCategoryIds({ response, count }: { response: JevResponse; count: number }): string[] {
  const answer = response.answers.category;
  if (answer?.type !== "choice") {
    throw new Error("Jev の応答に分類の答えがありません");
  }
  return Object.entries(answer.probabilities)
    .sort(([leftId, left], [rightId, right]) => (left !== right ? right - left : leftId.localeCompare(rightId)))
    .slice(0, count)
    .map(([categoryId]) => categoryId);
}

/** 同じ被写体の判定の候補 (既存のモンスターか、判定待ちの生成)。 */
export interface DedupeCandidate {
  /** 候補の識別子 (モンスターなら monsterId、判定待ちの生成なら `generation:<requestId>`)。 */
  candidateId: string;
  /** 候補の保存済みの説明。 */
  description: SubjectDescription;
}

/**
 * 新しい説明と候補の説明が「同じ個体」かを問うリクエストを、候補 `DEDUPE_CHUNK_SIZE` 件ごとに作る。
 * 問いは肯定 (`same__<n>`) と否定 (`different__<n>`) の対にし、3 値の判定表で読む (jev-question-design.md 1〜3)。
 */
export function buildDedupeRequests({
  description,
  candidates,
}: {
  description: SubjectDescription;
  candidates: DedupeCandidate[];
}): JevRequest[] {
  const requests: JevRequest[] = [];
  for (let start = 0; start < candidates.length; start += DEDUPE_CHUNK_SIZE) {
    const questions: Record<string, JevQuestion> = {};
    for (const [offset, candidate] of candidates.slice(start, start + DEDUPE_CHUNK_SIZE).entries()) {
      const index = start + offset;
      // 2 つの説明は同じ物でも別の写真から別々に書かれるため、言い回しの違いと、片方の写真にだけ写った手がかりを違いに数えないよう問いに書く
      // (較正の 1 回目で、同じ個体の対の否定側が 0.51〜0.76 と高く出たため。documents/game-rules.md「Jev の閾値」)。
      questions[`same__${index}`] = {
        type: "noul",
        instructions: {
          question:
            "state の subject と、この candidate は、同じ 1 つの物 (同じ個体) を別の時・別の角度から撮ったものか。2 つの説明は別々の写真から書いたもので、言い回しの違いや、片方の説明にだけ書かれた手がかり (角度で見えなかったもの) は違いに数えない。",
          candidate: candidate.description,
        },
        criteria: {
          true: "物の種類と、色・柄・素材が一致し、両方の説明に書かれた手がかり同士がはっきり矛盾しない",
          false: "物の種類が違う、または色・柄・素材のどれかがはっきり違う (例: 白い無地のマグカップと黄色い縞のマグカップ、陶器のマグカップとホーローのマグカップ、緑の多肉植物と白い斑点のある多肉植物)",
        },
      };
      questions[`different__${index}`] = {
        type: "noul",
        instructions: {
          question:
            "state の subject と、この candidate は、種類・色・柄・素材のどれかがはっきり違う、別々の物か。2 つの説明は別々の写真から書いたもので、言い回しの違いや、片方の説明にだけ書かれた手がかりは違いに数えない。",
          candidate: candidate.description,
        },
        criteria: {
          true: "物の種類、または色・柄・素材のどれかがはっきり違う (例: 白い無地のマグカップと黄色い縞のマグカップ、陶器のマグカップとホーローのマグカップ)",
          false: "物の種類・色・柄・素材が一致し、違いは言い回しか、片方の説明にだけ書かれた手がかりだけ",
        },
      };
    }
    requests.push({ model: JEV_MODEL, state: subjectState(description), questions });
  }
  return requests;
}

/** 同じ被写体の判定の閾値。値と実測の根拠は documents/game-rules.md「Jev の閾値」。 */
export interface DedupeThresholds {
  /** これ以上を「はい」とみなす。 */
  thresholdYes: number;
  /** これ以下を「いいえ」とみなす。 */
  thresholdNo: number;
}

/**
 * 同じ被写体の判定の閾値 (documents/game-rules.md「Jev の閾値」の実測で決めた値)。
 * 肯定が `thresholdYes` 以上かつ否定が `thresholdNo` 以下の時だけ同じ個体とする (揺れは別の物として扱い、登録を止めない)。
 */
export const DEDUPE_THRESHOLDS: DedupeThresholds = { thresholdYes: 0.65, thresholdNo: 0.35 };

/** 同じ個体と判定された候補の識別子を、肯定側の確率の高い順に返す。 */
export function sameSubjectCandidateIds({
  responses,
  candidates,
  thresholds,
}: {
  responses: JevResponse[];
  candidates: DedupeCandidate[];
  thresholds: DedupeThresholds;
}): string[] {
  const answers = Object.assign({}, ...responses.map((response) => response.answers)) as Record<string, JevAnswer>;
  return candidates
    .map((candidate, index) => {
      const same = answers[`same__${index}`];
      const different = answers[`different__${index}`];
      return {
        candidateId: candidate.candidateId,
        same: same?.type === "noul" ? same.noul : 0,
        different: different?.type === "noul" ? different.noul : 1,
      };
    })
    .filter(({ same, different }) => same >= thresholds.thresholdYes && different <= thresholds.thresholdNo)
    .sort((left, right) => right.same - left.same)
    .map(({ candidateId }) => candidateId);
}

/** ステータスごとの Score の問いの基準 (段階 0〜4 が master の statGrades の並びに対応する)。 */
const STAT_QUESTION_INSTRUCTIONS: Record<(typeof STAT_KINDS)[number], string> = {
  hitPoints: "この物をモンスターにした時の HP (打たれ強さ・持久力)。大きい・重い・どっしりした物ほど高く、小さい・薄い・壊れやすい物ほど低い。",
  attack: "この物をモンスターにした時の攻撃 (相手に与える力)。とがった・硬い・熱い・勢いのある物ほど高く、柔らかい・丸い・おとなしい物ほど低い。",
  defense: "この物をモンスターにした時の防御 (攻撃の受け止めやすさ)。硬い・厚い・頑丈な物ほど高く、柔らかい・薄い・割れやすい物ほど低い。",
  speed: "この物をモンスターにした時の素早さ。小さい・軽い・動く・転がる物ほど高く、大きい・重い・据え置きの物ほど低い。",
};

/**
 * 属性の当てはまり (Noul)・ステータスの段階 (Score)・属性ごとの技の選択 (Choice) を 1 リクエストで問う (ADR 0001「属性・技・ステータスの判定」)。
 * 技の Choice は、同じレベル帯に技が 2 つ以上ある属性だけに付ける (1 つしか無い帯は選ぶ余地が無いため)。
 */
export function buildJudgeRequest({
  description,
  elementTypes,
  moves,
  statGrades,
}: {
  description: SubjectDescription;
  elementTypes: MasterElementType[];
  moves: MasterMove[];
  statGrades: MasterStatGrade[];
}): JevRequest {
  const questions: Record<string, JevQuestion> = {};
  for (const elementType of elementTypes) {
    questions[`element__${elementType.id}`] = {
      type: "noul",
      instructions: `state の subject (写真の被写体) は「${elementType.displayName}」の属性に当てはまるか。`,
      criteria: {
        true: `subject の what・materials・uses のどれかが「${elementType.displayName}」の特徴に強く結びつく: ${elementType.description ?? elementType.displayName}`,
        false: `subject の what・materials・uses のどれも「${elementType.displayName}」の特徴に結びつかない、または結びつきが付け足し程度 (例: 金属の部品が少し付いているだけの布の物は金属に当てはまらない)`,
      },
    };
  }
  for (const statKind of STAT_KINDS) {
    questions[`stat__${statKind}`] = {
      type: "score",
      instructions: STAT_QUESTION_INSTRUCTIONS[statKind],
      criteria: statGrades.map((statGrade) => statGrade.displayName),
    };
  }
  for (const elementType of elementTypes) {
    const elementMoves = moves.filter((move) => move.elementTypeId === elementType.id);
    const levelBands = new Set(elementMoves.map((move) => move.learnableLevelMinimum));
    if (levelBands.size === elementMoves.length) {
      continue;
    }
    questions[`move__${elementType.id}`] = {
      type: "choice",
      instructions: "state の subject (写真の被写体) がモンスターになって使う技として、名前と威力が最も似合う技はどれか。",
      criteria: Object.fromEntries(elementMoves.map((move) => [move.id, `${move.displayName} (威力 ${move.power})`])),
    };
  }
  return { model: JEV_MODEL, state: subjectState(description), questions };
}

/** 判定の答えを、属性の確率・ステータスの段階・属性ごとの技の確率に分けて返す。 */
export function readJudgeResponse({
  response,
  statGrades,
}: {
  response: JevResponse;
  statGrades: MasterStatGrade[];
}): {
  elementProbabilities: Record<string, number>;
  statGradeIds: Record<(typeof STAT_KINDS)[number], string>;
  moveProbabilitiesByElement: Record<string, Record<string, number>>;
} {
  const elementProbabilities: Record<string, number> = {};
  const moveProbabilitiesByElement: Record<string, Record<string, number>> = {};
  for (const [questionName, answer] of Object.entries(response.answers)) {
    const [kind, id] = questionName.split("__");
    if (kind === "element" && answer.type === "noul") {
      elementProbabilities[id] = answer.noul;
    }
    if (kind === "move" && answer.type === "choice") {
      moveProbabilitiesByElement[id] = answer.probabilities;
    }
  }
  if (Object.keys(elementProbabilities).length === 0) {
    // 属性の問いに 1 つも答えていない応答は、属性を選べない (既存の属性に寄せることもできない) ため、Jev が答えなかった時と同じく判定待ちにする
    throw new JevUnavailableError("Jev の応答に属性の答えがありません");
  }
  const gradeOf = (statKind: (typeof STAT_KINDS)[number]) => {
    const answer = response.answers[`stat__${statKind}`];
    if (answer?.type !== "score") {
      throw new Error(`Jev の応答に ${statKind} の段階がありません`);
    }
    // 期待値 (score) ではなく確率が最も高い段階を採る。期待値は両端の段階に届きにくく、とても低い・とても高いが出にくくなるため。
    const [bestLevel] = Object.entries(answer.probabilities).sort(([, left], [, right]) => right - left)[0];
    const statGrade = statGrades.find((grade) => grade.displayName === bestLevel) ?? statGrades[Number(bestLevel)];
    if (!statGrade) {
      throw new Error(`Jev の段階 ${bestLevel} が master の statGrades にありません`);
    }
    return statGrade.id;
  };
  return {
    elementProbabilities,
    statGradeIds: {
      hitPoints: gradeOf("hitPoints"),
      attack: gradeOf("attack"),
      defense: gradeOf("defense"),
      speed: gradeOf("speed"),
    },
    moveProbabilitiesByElement,
  };
}

/**
 * Claude が提案した新しい属性と、既存のその場で作った属性が同じ意味かを問う (ADR 0001「master に無い属性・技」)。
 * その場で作った属性が無い間は呼ばない。
 */
export function buildSameDefinitionRequest({
  proposal,
  existingElementTypes,
}: {
  proposal: MasterElementType;
  existingElementTypes: MasterElementType[];
}): JevRequest {
  return {
    model: JEV_MODEL,
    state: { proposedElement: proposal },
    questions: Object.fromEntries(
      existingElementTypes.map((elementType) => [
        `same_element__${elementType.id}`,
        {
          type: "noul",
          instructions: { question: "state の proposedElement と、この existingElement は、同じ性質を表す属性か (名前が違っても意味が同じなら同じ)。", existingElement: elementType },
          criteria: {
            true: "2 つの属性が表す素材・性質・現象が同じで、どちらに分類しても違和感が無い",
            false: "2 つの属性が表す素材・性質・現象が違う",
          },
        } satisfies JevQuestion,
      ]),
    ),
  };
}
