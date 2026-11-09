// Action Card (技を 1 つ買い切り、本人のモンスターに何体にでも何回でも覚えさせる消耗型の商品) の、Firestore に依存しない規則。
// 決めた値と根拠は documents/DIRECTION.md「決めたこと」2026-11-09 の #271 の行と documents/game-rules.md「Action Card」。

import { battleDayKey } from "./battle_rules";
import type { MasterMove } from "./generation/master";
import type { LearnsetEntry } from "./generation/monster_stats";

/** 技のランク。1 が 100 円、2 が 300 円、3 が 500 円のカードに当たる (価格はストアが正で、ここには持たない)。 */
export type MoveRank = 1 | 2 | 3;

/** ランクの一覧 (安い順)。 */
export const MOVE_RANKS: readonly MoveRank[] = [1, 2, 3];

/**
 * 1 体が同時に使える技の数。lib/domain/battle/battle_engine.dart の `maximumEquippedMoveCount` と同じ値
 * (生まれた時に Lv.1 でそろう技の数 `STARTING_MOVE_COUNT` と同じ)。
 */
export const MAXIMUM_EQUIPPED_MOVE_COUNT = 4;

/**
 * ランクを決める使用回数の集計の期間 (日)。仮の値: 曜日ごとの遊ばれ方の偏りがならされる最短の 1 週間にした
 * (owner の「為替みたいによく使われる技によって変動」を、毎日の入れ替えで追える長さにするため。#271)。
 */
export const MOVE_USAGE_WINDOW_DAYS = 7;

/**
 * 使われた技のうちランク 3 にする割合 (%)。仮の値: 高い段が多すぎると 500 円の技がありふれて見えるため、上位の 2 割にした (#271)。
 */
export const RANK_3_USAGE_PERCENT = 20;

/**
 * 使われた技のうちランク 2 にする割合 (%)。仮の値: ランク 3 の次の 3 割にし、残りの 5 割を 100 円のランク 1 にして、
 * 安いカードで買える技が一番多くなるようにした (#271)。
 */
export const RANK_2_USAGE_PERCENT = 30;

/**
 * 段階で決める予備のランクのしきい値の威力。110 は段階 3 の技の威力、70 は段階 2 の技の威力
 * (documents/game-rules.md「技」の表)。段階 3 と同じ強さの技を 500 円、段階 2 と同じ強さの技を 300 円にするため。
 */
const RANK_3_MINIMUM_POWER = 110;
const RANK_2_MINIMUM_POWER = 70;

/** 商品の識別子の接頭辞とランク。識別子の残り (価格の `_100yen`・`_150yen`) は見ない (Google Play で 100 円を設定できない時に 150 円へ変えるため。#271)。 */
const ACTION_CARD_PRODUCT_ID_PATTERN = /^snapmon_actioncardrank([123])_/;

/** [productId] が Action Card の商品ならそのランク、それ以外は undefined。 */
export function actionCardRankOfProduct(productId: string | null): MoveRank | undefined {
  const match = productId === null ? null : ACTION_CARD_PRODUCT_ID_PATTERN.exec(productId);
  return match ? (Number(match[1]) as MoveRank) : undefined;
}

/**
 * [learnset] と [actionCardMoveIds] のモンスターが [level] で使える技 (技の枠) の ID を、枠の順で返す。
 * 枠は「[learnset] のうち開放レベルが [level] 以下の技を一覧の順に並べ、[actionCardMoveIds] を覚えさせた順で続けた列」の後ろ
 * [MAXIMUM_EQUIPPED_MOVE_COUNT] 個。[actionCardMoveIds] に入った技は learnset 側の列から外す (同じ技が枠に 2 つ並ばないようにし、
 * 覚えさせた技を一番新しい技として扱うため。documents/game-rules.md「技」)。
 * [actionCardMoveIds] が空なら lib/domain/battle/battle_engine.dart の `equippedLearnsetEntries` と同じ技を返す
 * (共通のテストケースは test/fixtures/equipped_move_cases.json)。
 */
export function equippedMoveIds({
  learnset,
  level,
  actionCardMoveIds,
}: {
  learnset: LearnsetEntry[];
  level: number;
  actionCardMoveIds: string[];
}): string[] {
  const moveIds = [
    ...learnset.filter((entry) => entry.unlockLevel <= level && !actionCardMoveIds.includes(entry.moveId)).map((entry) => entry.moveId),
    ...actionCardMoveIds,
  ];
  return moveIds.slice(Math.max(0, moveIds.length - MAXIMUM_EQUIPPED_MOVE_COUNT));
}

/**
 * 使用回数の集計が無い技のランク (技の段階で決める予備のランク)。威力 [RANK_3_MINIMUM_POWER] 以上 (段階 3・自爆) と一撃必殺は 3、
 * 威力 [RANK_2_MINIMUM_POWER] 以上 (段階 2) と先制・必中の技は 2、それ以外は 1。
 */
export function fallbackMoveRank(move: MasterMove): MoveRank {
  if (move.power >= RANK_3_MINIMUM_POWER || move.specialEffect?.oneHitKnockout === true) {
    return 3;
  }
  if (move.power >= RANK_2_MINIMUM_POWER || (move.priority ?? 0) > 0 || move.specialEffect?.sureHit === true) {
    return 2;
  }
  return 1;
}

/**
 * [moves] (買える技) のランクを決める。[usageCountByMoveId] で 1 回以上使われた技を使用回数の多い順 (同じ回数は技の ID の順) に並べ、
 * 使われた技の数の [RANK_3_USAGE_PERCENT]% (切り捨て) までをランク 3、[RANK_3_USAGE_PERCENT] + [RANK_2_USAGE_PERCENT]% (切り捨て) までを
 * ランク 2、残りをランク 1 にする。使われていない技は [fallbackMoveRank] で決める。
 * 割合の母数を使われた技の数にするのは、使われた技が少ない間に、使用 0 の技どうしの並びで段を分けないため。
 */
export function computeMoveRanks({
  moves,
  usageCountByMoveId,
}: {
  moves: MasterMove[];
  usageCountByMoveId: Record<string, number>;
}): Record<string, MoveRank> {
  const usageCountOf = (move: MasterMove) => (Object.hasOwn(usageCountByMoveId, move.id) ? usageCountByMoveId[move.id] : 0);
  const usedMoves = moves
    .filter((move) => usageCountOf(move) > 0)
    .sort((left, right) => usageCountOf(right) - usageCountOf(left) || (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
  const rank3Count = Math.floor((usedMoves.length * RANK_3_USAGE_PERCENT) / 100);
  const rank2OrHigherCount = Math.floor((usedMoves.length * (RANK_3_USAGE_PERCENT + RANK_2_USAGE_PERCENT)) / 100);
  const usageRankByMoveId = new Map<string, MoveRank>(
    usedMoves.map((move, index): [string, MoveRank] => [move.id, index < rank3Count ? 3 : index < rank2OrHigherCount ? 2 : 1]),
  );
  return Object.fromEntries(moves.map((move) => [move.id, usageRankByMoveId.get(move.id) ?? fallbackMoveRank(move)]));
}

/**
 * ランク [moveRank] の技を買う時に使うカードのランク。[credits] (ランクごとの残高) のうち、[moveRank] 以上で残高のある一番安いランク。
 * 高いカードで安い技を買える (#271) が、安いカードが残っている時に高いカードを減らさないため一番安いものから使う。使えるカードが無ければ undefined。
 */
export function creditRankToRedeem({ moveRank, credits }: { moveRank: MoveRank; credits: Record<MoveRank, number> }): MoveRank | undefined {
  return MOVE_RANKS.find((creditRank) => creditRank >= moveRank && credits[creditRank] >= 1);
}

/** `users/{uid}.actionCardCredits` の値 [stored] を、ランクごとの残高にする。無いランクは 0 枚 (買っていない)。 */
export function actionCardCreditsOf(stored: unknown): Record<MoveRank, number> {
  const credits = (stored ?? {}) as Partial<Record<`rank${MoveRank}`, unknown>>;
  const countOf = (value: unknown) => (typeof value === "number" ? value : 0);
  return { 1: countOf(credits.rank1), 2: countOf(credits.rank2), 3: countOf(credits.rank3) };
}

/**
 * [now] の日本時間の前日から遡った [days] 日分の日付 (`YYYY-MM-DD`。区切りは [battleDayKey])。ランクの集計の期間に使う。
 * 当日を含めないのは、集計が日本時間の 4 時に動き、当日の分が 4 時間しか無いため。
 */
export function previousDayKeys({ now, days }: { now: Date; days: number }): string[] {
  return Array.from({ length: days }, (_, index) => battleDayKey({ now: new Date(now.getTime() - (index + 1) * 24 * 60 * 60 * 1000) }));
}
