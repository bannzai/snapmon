// Claude API の呼び出し (被写体の説明と、新しい属性の提案)。クライアントは anthropic.ts が WIF で作る。

import type Anthropic from "@anthropic-ai/sdk";

import {
  DESCRIBE_SUBJECT_OUTPUT_SCHEMA,
  DESCRIBE_SUBJECT_SYSTEM_PROMPT,
  type DescribeSubjectOutput,
  parseDescribeSubjectOutput,
  type SubjectDescription,
} from "./prompts/describe_subject";
import { PROPOSE_ELEMENT_OUTPUT_SCHEMA, PROPOSE_ELEMENT_SYSTEM_PROMPT, type ProposeElementOutput } from "./prompts/propose_element";

/**
 * 使うモデル。claude-api skill の既定 (Claude Opus 5.5) に従った。1 体あたりの原価は ADR 0002 に見積もりを書き、
 * 本番の実測 (生成レコードの `claudeUsage`) で見直す。
 */
export const CLAUDE_MODEL = "claude-opus-5-5";

/** 出力の上限。説明・名前・文章・装飾の JSON は実測で 800 トークン前後 (ADR 0002) のため、思考の分を含めて余裕を持たせた。 */
const MAX_TOKENS = 8_000;

/**
 * 1 回の呼び出しの待ち時間 (ミリ秒) と再試行の回数。SDK の既定 (10 分・2 回) のままだと、関数のタイムアウト (generate.ts の 300 秒)
 * を過ぎても応答を待ち続けるため、2 回分 (120 秒) が関数のタイムアウトに収まる値にした。
 */
const CLAUDE_REQUEST_OPTIONS = { timeout: 60_000, maxRetries: 1 };

/** Claude のトークンの使用量。原価の実測のため生成レコードに残す。 */
export interface ClaudeUsage {
  /** 入力トークン数。 */
  inputTokens: number;
  /** 出力トークン数。 */
  outputTokens: number;
}

/** Claude が安全上の理由で答えなかったこと (`stop_reason: refusal`) を表す。生成は拒否として終える。 */
export class ClaudeRefusalError extends Error {}

/** 被写体の説明を作る関数。テストではモックに差し替える。 */
export type DescribeSubject = (cutoutJpeg: Buffer) => Promise<{ output: DescribeSubjectOutput; usage: ClaudeUsage }>;

/** 新しい属性を提案させる関数。テストではモックに差し替える。 */
export type ProposeElement = (input: {
  description: SubjectDescription;
  existingElementNames: string[];
}) => Promise<{ output: ProposeElementOutput; usage: ClaudeUsage }>;

/**
 * structured outputs で JSON を返させ、最初のテキストブロックを返す。
 * 安全上の理由で答えなかった時は既定のモデルの組へ落とす (claude-api skill の既定の server-side fallback)。それでも拒否なら `ClaudeRefusalError`。
 */
async function createStructuredMessage({
  client,
  system,
  schema,
  content,
}: {
  client: Anthropic;
  system: string;
  schema: Record<string, unknown>;
  content: Anthropic.Beta.Messages.BetaContentBlockParam[];
}): Promise<{ text: string; usage: ClaudeUsage }> {
  const response = await client.beta.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: MAX_TOKENS,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    // 低い effort: 写真 1 枚の説明と短い文章で、深い推論が要らないため (claude-api skill「Choosing an effort level」)。
    output_config: { effort: "low", format: { type: "json_schema", schema } },
    system,
    messages: [{ role: "user", content }],
  }, CLAUDE_REQUEST_OPTIONS);
  if (response.stop_reason === "refusal") {
    throw new ClaudeRefusalError("Claude が安全上の理由で答えませんでした");
  }
  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new Error(`Claude の応答にテキストがありません (stop_reason: ${response.stop_reason})`);
  }
  return { text: textBlock.text, usage: { inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens } };
}

/** 被写体の説明を作る関数を作る。 */
export function createDescribeSubject(getClient: () => Anthropic): DescribeSubject {
  return async (cutoutJpeg) => {
    const { text, usage } = await createStructuredMessage({
      client: getClient(),
      system: DESCRIBE_SUBJECT_SYSTEM_PROMPT,
      schema: DESCRIBE_SUBJECT_OUTPUT_SCHEMA,
      content: [
        { type: "image", source: { type: "base64", media_type: "image/jpeg", data: cutoutJpeg.toString("base64") } },
        { type: "text", text: "この被写体について JSON を返してください。" },
      ],
    });
    return { output: parseDescribeSubjectOutput(text), usage };
  };
}

/** 新しい属性を提案させる関数を作る。 */
export function createProposeElement(getClient: () => Anthropic): ProposeElement {
  return async ({ description, existingElementNames }) => {
    const { text, usage } = await createStructuredMessage({
      client: getClient(),
      system: PROPOSE_ELEMENT_SYSTEM_PROMPT,
      schema: PROPOSE_ELEMENT_OUTPUT_SCHEMA,
      content: [{ type: "text", text: JSON.stringify({ subject: description, existingElementNames }) }],
    });
    return { output: JSON.parse(text) as ProposeElementOutput, usage };
  };
}
