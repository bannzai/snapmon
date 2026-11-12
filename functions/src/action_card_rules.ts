// Action Card (技を 1 つ選んで買い切り、本人のモンスターに何体にでも何回でも覚えさせる消耗型の商品) の、Firestore に依存しない規則。
// 決めた値と根拠は documents/DIRECTION.md「決めたこと」2026-11-09 の #271 の行と documents/game-rules.md「Action Card」。

import { battleDayKey } from "./battle_rules";
import type { MasterMove } from "./generation/master";
import type { LearnsetEntry } from "./generation/monster_stats";

/**
 * 人気の上位の技と強い技に割り振る Action Card の商品 ID (500 円)。商品 ID は App Store・Google Play・RevenueCat で同じ
 * (~/.claude/documents/rules/iap-product-identifier-naming.md)。価格はストアが正で、ここには持たない。
 * 3 つの商品 ID を書くのは、割り振りを決めるこのファイルだけにする (アプリと webhook は技に割り振った商品 ID をそのまま使う。#293)。
 */
export const EXPENSIVE_ACTION_CARD_PRODUCT_ID = "snapmon_actioncardrank3_500yen";

/** 人気が中くらいの技と中くらいの強さの技に割り振る Action Card の商品 ID (300 円)。 */
export const MODERATE_ACTION_CARD_PRODUCT_ID = "snapmon_actioncardrank2_300yen";

/** 残りの技に割り振る Action Card の商品 ID (100 円)。 */
export const CHEAP_ACTION_CARD_PRODUCT_ID = "snapmon_actioncardrank1_100yen";

/** Action Card の商品 ID の一覧。webhook が届いた商品を Action Card と見分けるのに使う。 */
export const ACTION_CARD_PRODUCT_IDS: readonly string[] = [CHEAP_ACTION_CARD_PRODUCT_ID, MODERATE_ACTION_CARD_PRODUCT_ID, EXPENSIVE_ACTION_CARD_PRODUCT_ID];

/**
 * 1 体が同時に使える技の数。lib/domain/battle/battle_engine.dart の `maximumEquippedMoveCount` と同じ値
 * (生まれた時に Lv.1 でそろう技の数 `STARTING_MOVE_COUNT` と同じ)。
 */
export const MAXIMUM_EQUIPPED_MOVE_COUNT = 4;

/**
 * 技に割り振る商品を決める使用回数の集計の期間 (日)。仮の値: 曜日ごとの遊ばれ方の偏りがならされる最短の 1 週間にした
 * (owner の「為替みたいによく使われる技によって変動」を、毎日の入れ替えで追える長さにするため。#271)。
 */
export const MOVE_USAGE_WINDOW_DAYS = 7;

/**
 * 買える技のうち [EXPENSIVE_ACTION_CARD_PRODUCT_ID] を割り振る割合 (%)。仮の値: 高い段が多すぎると 500 円の技がありふれて見えるため、
 * 上位の 2 割にした (#271)。
 */
export const EXPENSIVE_PRODUCT_USAGE_PERCENT = 20;

/**
 * 買える技のうち [MODERATE_ACTION_CARD_PRODUCT_ID] を割り振る割合 (%)。仮の値: 500 円の次の 3 割にし、残りの 5 割を 100 円にして、
 * 安いカードで買える技が一番多くなるようにした (#271)。
 */
export const MODERATE_PRODUCT_USAGE_PERCENT = 30;

/**
 * 段階で決める予備の商品で [EXPENSIVE_ACTION_CARD_PRODUCT_ID] にする最小の威力。110 は段階 3 の技の威力
 * (documents/game-rules.md「技」の表) で、段階 3 と同じ強さの技を 500 円にするため。
 */
const EXPENSIVE_PRODUCT_MINIMUM_POWER = 110;

/**
 * 段階で決める予備の商品で [MODERATE_ACTION_CARD_PRODUCT_ID] にする最小の威力。70 は段階 2 の技の威力
 * (documents/game-rules.md「技」の表) で、段階 2 と同じ強さの技を 300 円にするため。
 */
const MODERATE_PRODUCT_MINIMUM_POWER = 70;

/** [productID] が Action Card の商品か。 */
export function isActionCardProductID(productID: string | null): productID is string {
  return productID !== null && ACTION_CARD_PRODUCT_IDS.includes(productID);
}

/**
 * [learnset] と [actionCardMoveIDs] のモンスターが [level] で持っている技 (対戦の前に技の枠へ選べる技) の ID を、
 * 「[learnset] のうち開放レベルが [level] 以下の技を一覧の順に並べ、[actionCardMoveIDs] を覚えさせた順で続けた列」で返す。
 * [actionCardMoveIDs] に入った技は learnset 側の列から外す (同じ技が 2 つ並ばないようにし、覚えさせた技を一番新しい技として扱うため。
 * documents/game-rules.md「技」)。lib/domain/battle/battle_engine.dart の `availableMoveIDs` と同じ列を返す。
 */
export function availableMoveIDs({
  learnset,
  level,
  actionCardMoveIDs,
}: {
  learnset: LearnsetEntry[];
  level: number;
  actionCardMoveIDs: string[];
}): string[] {
  return [
    ...learnset
      .filter((learnsetEntry) => learnsetEntry.unlockLevel <= level && !actionCardMoveIDs.includes(learnsetEntry.moveID))
      .map((learnsetEntry) => learnsetEntry.moveID),
    ...actionCardMoveIDs,
  ];
}

/**
 * [learnset]・[actionCardMoveIDs]・[selectedMoveIDs] (対戦の前に選んだ技の ID。枠の順。選んでいなければ undefined) のモンスターが
 * [level] で使える技 (技の枠) の ID を、枠の順で返す。
 * [selectedMoveIDs] のうち今も持っている技 ([availableMoveIDs]) が 1 つ以上あれば、それを選んだ順で枠にする。無ければ持っている技の列の後ろ
 * [MAXIMUM_EQUIPPED_MOVE_COUNT] 個を、列の i 番目の技を i を [MAXIMUM_EQUIPPED_MOVE_COUNT] で割った余りの枠に置いて返す
 * (新しく覚えた技が外れた技の枠に入り、残る技の枠を変えないため。#309)。規則は documents/game-rules.md「技」。
 * lib/domain/battle/battle_engine.dart の `equippedLearnsetEntries` と同じ技を同じ順で返す (共通のテストケースは test/fixtures/equipped_move_cases.json)。
 */
export function equippedMoveIDs({
  learnset,
  level,
  actionCardMoveIDs,
  selectedMoveIDs,
}: {
  learnset: LearnsetEntry[];
  level: number;
  actionCardMoveIDs: string[];
  selectedMoveIDs: string[] | undefined;
}): string[] {
  const moveIDs = availableMoveIDs({ learnset, level, actionCardMoveIDs });
  const selectedAvailableMoveIDs = [...new Set(selectedMoveIDs ?? [])]
    .filter((moveID) => moveIDs.includes(moveID))
    .slice(0, MAXIMUM_EQUIPPED_MOVE_COUNT);
  if (selectedAvailableMoveIDs.length > 0) {
    return selectedAvailableMoveIDs;
  }
  const windowStart = Math.max(0, moveIDs.length - MAXIMUM_EQUIPPED_MOVE_COUNT);
  return Array.from(
    { length: moveIDs.length - windowStart },
    (_, slotIndex) => moveIDs[windowStart + (((slotIndex - windowStart) % MAXIMUM_EQUIPPED_MOVE_COUNT) + MAXIMUM_EQUIPPED_MOVE_COUNT) % MAXIMUM_EQUIPPED_MOVE_COUNT],
  );
}

/**
 * 対戦の前に選ぶ技 [moveIDs] (枠の順) を [availableMoveIDs] (モンスターが持っている技) の中から選べているかを確かめ、
 * 選べていなければ断る理由を、選べていれば null を返す。1 つ以上 [MAXIMUM_EQUIPPED_MOVE_COUNT] 個以下で、重複が無く、
 * すべて持っている技であること (技の枠が空のまま戦えず、持っていない技を改ざんで使わせないため)。
 */
export function selectedMoveIDsRejectionReason({
  moveIDs,
  availableMoveIDs,
}: {
  moveIDs: string[];
  availableMoveIDs: string[];
}): string | null {
  if (moveIDs.length === 0 || moveIDs.length > MAXIMUM_EQUIPPED_MOVE_COUNT) {
    return `技は 1 つ以上 ${MAXIMUM_EQUIPPED_MOVE_COUNT} つ以下で選んでください`;
  }
  if (new Set(moveIDs).size !== moveIDs.length) {
    return "同じ技を 2 回選んでいます";
  }
  const unavailableMoveID = moveIDs.find((moveID) => !availableMoveIDs.includes(moveID));
  if (unavailableMoveID !== undefined) {
    return `${unavailableMoveID} はまだ覚えていません`;
  }
  return null;
}

/**
 * 使用回数の集計が無い技の商品 ID (技の段階で決める予備の商品)。威力 [EXPENSIVE_PRODUCT_MINIMUM_POWER] 以上 (段階 3・自爆) と一撃必殺は
 * [EXPENSIVE_ACTION_CARD_PRODUCT_ID]、威力 [MODERATE_PRODUCT_MINIMUM_POWER] 以上 (段階 2) と先制・必中の技は [MODERATE_ACTION_CARD_PRODUCT_ID]、
 * それ以外は [CHEAP_ACTION_CARD_PRODUCT_ID]。
 */
export function fallbackActionCardProductID(move: MasterMove): string {
  if (move.power >= EXPENSIVE_PRODUCT_MINIMUM_POWER || move.specialEffect?.oneHitKnockout === true) {
    return EXPENSIVE_ACTION_CARD_PRODUCT_ID;
  }
  if (move.power >= MODERATE_PRODUCT_MINIMUM_POWER || (move.priority ?? 0) > 0 || move.specialEffect?.sureHit === true) {
    return MODERATE_ACTION_CARD_PRODUCT_ID;
  }
  return CHEAP_ACTION_CARD_PRODUCT_ID;
}

/**
 * [moves] (買える技) に Action Card の商品 ID を割り振り、技の ID ごとの商品 ID を返す。[moves] を [usageCountByMoveID] の使用回数の多い順
 * (同じ回数は技の ID の順) に並べ、[moves] の数の [EXPENSIVE_PRODUCT_USAGE_PERCENT]% (切り捨て) までを [EXPENSIVE_ACTION_CARD_PRODUCT_ID]、
 * [EXPENSIVE_PRODUCT_USAGE_PERCENT] + [MODERATE_PRODUCT_USAGE_PERCENT]% (切り捨て) までを [MODERATE_ACTION_CARD_PRODUCT_ID]、
 * 残りを [CHEAP_ACTION_CARD_PRODUCT_ID] にする。ただし使用回数が 0 の技は、並びの位置に関係なく [fallbackActionCardProductID] で決める
 * (issue #271 の「上位 20% を 500 円」と「使用回数が 0 の技は技の段階で決める」の両方をそのまま満たすため)。
 */
export function computeActionCardProductIDByMoveID({
  moves,
  usageCountByMoveID,
}: {
  moves: MasterMove[];
  usageCountByMoveID: Record<string, number>;
}): Record<string, string> {
  const usageCountOf = (move: MasterMove) => (Object.hasOwn(usageCountByMoveID, move.id) ? usageCountByMoveID[move.id] : 0);
  return Object.fromEntries(
    [...moves]
      .sort((left, right) => usageCountOf(right) - usageCountOf(left) || (left.id < right.id ? -1 : left.id > right.id ? 1 : 0))
      .map((move, index): [string, string] => [
        move.id,
        usageCountOf(move) === 0
          ? fallbackActionCardProductID(move)
          : index < Math.floor((moves.length * EXPENSIVE_PRODUCT_USAGE_PERCENT) / 100)
            ? EXPENSIVE_ACTION_CARD_PRODUCT_ID
            : index < Math.floor((moves.length * (EXPENSIVE_PRODUCT_USAGE_PERCENT + MODERATE_PRODUCT_USAGE_PERCENT)) / 100)
              ? MODERATE_ACTION_CARD_PRODUCT_ID
              : CHEAP_ACTION_CARD_PRODUCT_ID,
      ]),
  );
}

/**
 * [now] の日本時間の前日から遡った [days] 日分の日付 (`YYYY-MM-DD`。区切りは [battleDayKey])。技に割り振る商品の集計の期間に使う。
 * 当日を含めないのは、集計が日本時間の 4 時に動き、当日の分が 4 時間しか無いため。
 */
export function previousDayKeys({ now, days }: { now: Date; days: number }): string[] {
  return Array.from({ length: days }, (_, index) => battleDayKey({ now: new Date(now.getTime() - (index + 1) * 24 * 60 * 60 * 1000) }));
}
