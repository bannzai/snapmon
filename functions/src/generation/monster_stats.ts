// ステータス・属性・覚える技を、保存した説明と Jev の判定から決定的に決める計算。
// 式は Dart の lib/domain/monster/stat_calculation.dart と lib/domain/random/deterministic_random.dart を写したもので、
// 両者が同じ値を返すことを functions/test/unit/monster_stats.test.ts が Dart 側のテストと同じ期待値で確かめる。
// 計算をサーバーに置くのは、モンスターの値を Functions だけが書く (クライアントに値を決めさせない) ため (ADR 0002)。
// 式を変える時は Dart 側と同時に変え、版 (`CURRENT_STAT_CALCULATION_VERSION`) を上げる。

import type { Master, MasterMove } from "./master";

/** 新しく生まれるモンスターに保存するステータスの計算手順の版 (Dart の `currentStatCalculationVersion` と同じ値)。 */
export const CURRENT_STAT_CALCULATION_VERSION = 1;

/** 個体値の上限 (Dart の `individualValueMaximum` と同じ値。根拠はそちらのコメント)。 */
const INDIVIDUAL_VALUE_MAXIMUM = 31;

const UINT32_MASK = 0xffffffff;

/** HP・攻撃・防御・素早さの 4 つの値。Dart の `MonsterStats` の JSON と同じ形。 */
export interface MonsterStats {
  /** HP。 */
  hitPoints: number;
  /** 攻撃。 */
  attack: number;
  /** 防御。 */
  defense: number;
  /** 素早さ。 */
  speed: number;
}

/** ステータスの種類。Jev の Score の問いの名前と、`MonsterStats` のキーに使う。 */
export const STAT_KINDS = ["hitPoints", "attack", "defense", "speed"] as const;

/** モンスターが覚える技の 1 件。Dart の `LearnsetEntry` の JSON と同じ形。 */
export interface LearnsetEntry {
  /** 技の識別子。 */
  moveId: string;
  /** 使えるようになるレベル。 */
  unlockLevel: number;
}

/** [text] の UTF-8 のバイト列から FNV-1a (32 bit) を返す (Dart の `fnv1a32` と同じ値)。 */
export function fnv1a32(text: string): number {
  // FNV-1a 32 bit の offset basis と prime (http://www.isthe.com/chongo/tech/comp/fnv/ の定数)
  let hash = 0x811c9dc5;
  for (const byte of Buffer.from(text, "utf8")) {
    hash ^= byte;
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash >>> 0;
}

/**
 * seed から xorshift32 で値を引く関数を返す (Dart の `DeterministicRandom` と同じ列)。
 * xorshift32 は状態 0 から抜け出せないため、0 は FNV-1a の offset basis に置き換える (Dart と同じ値)。
 */
function deterministicRandom(seed: number): (range: { minimum: number; maximum: number }) => number {
  let state = (seed & UINT32_MASK) >>> 0 === 0 ? 0x811c9dc5 : (seed & UINT32_MASK) >>> 0;
  return ({ minimum, maximum }) => {
    state ^= state << 13;
    state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5;
    state >>>= 0;
    return minimum + (state % (maximum - minimum + 1));
  };
}

/** 保存した被写体の説明文から、個体値 (各 0〜31) を決定的に引く。引く順番は HP・攻撃・防御・素早さで固定する。 */
export function individualValuesFromDescription(subjectDescriptionText: string): MonsterStats {
  const next = deterministicRandom(fnv1a32(subjectDescriptionText));
  return {
    hitPoints: next({ minimum: 0, maximum: INDIVIDUAL_VALUE_MAXIMUM }),
    attack: next({ minimum: 0, maximum: INDIVIDUAL_VALUE_MAXIMUM }),
    defense: next({ minimum: 0, maximum: INDIVIDUAL_VALUE_MAXIMUM }),
    speed: next({ minimum: 0, maximum: INDIVIDUAL_VALUE_MAXIMUM }),
  };
}

/** Jev が判定したステータスごとの段階 (段階の `id`) から種族値を返す。段階が master に無ければ throw する。 */
export function baseStatsFromStatGrades({
  statGradeIds,
  master,
}: {
  statGradeIds: Record<(typeof STAT_KINDS)[number], string>;
  master: Master;
}): MonsterStats {
  const baseStatOf = (statKind: (typeof STAT_KINDS)[number]) => {
    const statGrade = master.statGrades.find((grade) => grade.id === statGradeIds[statKind]);
    if (!statGrade) {
      throw new Error(`段階 ${statGradeIds[statKind]} が master に無い`);
    }
    return statGrade.baseStat;
  };
  return {
    hitPoints: baseStatOf("hitPoints"),
    attack: baseStatOf("attack"),
    defense: baseStatOf("defense"),
    speed: baseStatOf("speed"),
  };
}

/**
 * 属性ごとの当てはまりの確率から、確率が閾値以上の属性を確率の高い順 (同じなら ID 順) に上限まで返す (Dart の `selectElementTypeIds` と同じ規則)。
 * 空の配列はどの属性にも当てはまらないことを表し、その場で新しい属性を作る経路に進む。
 */
export function selectElementTypeIds({
  elementProbabilities,
  master,
}: {
  elementProbabilities: Record<string, number>;
  master: Master;
}): string[] {
  return Object.entries(elementProbabilities)
    .filter(([, probability]) => probability >= master.elementSelection.probabilityThreshold)
    .sort(([leftId, left], [rightId, right]) => (left !== right ? right - left : leftId.localeCompare(rightId)))
    .slice(0, master.elementSelection.maximumCount)
    .map(([elementTypeId]) => elementTypeId);
}

/** 生まれた時 (Lv.1) に使える技の数。バトル画面の技の枠の数 (Dart の `maximumEquippedMoveCount`) と同じ値。 */
export const STARTING_MOVE_COUNT = 4;

/**
 * 生まれた時に使える技のうち、自分の属性の技の数の上限。残りは別の属性の技にする (#224。自分の属性だけだと、同じ属性のモンスターが
 * どれも同じ技で生まれ、相性の悪い相手に何もできないため)。属性が 2 つなら 1 つずつ。
 */
export const STARTING_OWN_ELEMENT_MOVE_COUNT = 2;

/** 生まれた時から使える技のレベル帯の下限 (master の段階 1 とその場で作った定義の段階 1 の `learnableLevelMinimum`)。 */
const STARTING_LEVEL = 1;

/**
 * Lv.2 以降に技を覚えるレベルを順に返す。Lv.2・Lv.3 で 1 つずつ、以降は 2 と 3 を交互に足したレベル (5, 8, 10, 13, 15, 18, 20, ...) で 1 つずつ覚える
 * (#224。1 戦でレベルが 1 上がるため、序盤は数戦ごとに新しい技が増え、慣れた後はおよそ 5 レベルに 2 つの速さにした)。
 */
export function laterLearnLevel({ index }: { index: number }): number {
  if (index < 2) {
    return index + 2;
  }
  const pairs = Math.floor((index - 2) / 2);
  return 5 + pairs * 5 + ((index - 2) % 2 === 0 ? 0 : 3);
}

/** 覚える技の一覧で、攻撃技の間に補助技を挟む間隔。攻撃技 2 つにつき補助技 1 つにし、開放の新しい 4 つ (技の枠) に攻撃技が 2 つ以上残るようにする。 */
const SUPPORT_MOVE_INTERVAL = 3;

/**
 * 属性ごとの技の確率 (Jev の Choice の `probabilities`) から覚える技の一覧を組む。
 * Lv.1 の技は `STARTING_MOVE_COUNT` 個そろえる: 自分の属性の段階 1 の技を確率の高い順 (同じなら [moves] の順) に属性の順に 1 つずつ交互に
 * `STARTING_OWN_ELEMENT_MOVE_COUNT` 個まで取り、残りは [fallbackMoves] の別の属性の段階 1 の技から、当てはまりの確率 [elementProbabilities] が高い順 (同じなら ID 順) に 1 つずつ足す。
 * Lv.2 以降は、自分の属性の残りの技を、攻撃技と補助技に分けてそれぞれレベル帯の下限 → Jev の確率が高い順 → [moves] の順に並べ (属性が 2 つなら交互)、
 * 攻撃技 2 つに補助技 1 つの間隔で混ぜ、`laterLearnLevel` の順のレベルで 1 つずつ覚える。開放レベルはそのレベルとレベル帯の下限の大きい方。候補が尽きたら終わり。
 * 並びは開放レベル順 (同じレベルは覚える順)。
 * [fallbackMoves] には master の技を渡す (その場で作った別の属性の技はモンスターの `definitionIds` に入らず、端末で引けないため)。
 */
export function buildLearnset({
  elementTypeIds,
  elementProbabilities,
  moveProbabilitiesByElement,
  moves,
  fallbackMoves,
}: {
  elementTypeIds: string[];
  elementProbabilities: Record<string, number>;
  moveProbabilitiesByElement: Record<string, Record<string, number>>;
  moves: MasterMove[];
  fallbackMoves: MasterMove[];
}): LearnsetEntry[] {
  /** [elementTypeId] の技の確率が高い順 (同じなら元の順) に [candidates] を並べ替えて返す。 */
  const sortByProbability = ({ elementTypeId, candidates }: { elementTypeId: string; candidates: MasterMove[] }) => {
    const probabilities = moveProbabilitiesByElement[elementTypeId] ?? {};
    return [...candidates].sort((left, right) => (probabilities[right.id] ?? 0) - (probabilities[left.id] ?? 0));
  };
  /** [candidates] のうち [elementTypeId] の段階 1 の技を、Jev の技の確率が高い順 (同じなら [candidates] の順) で返す。 */
  const startingMovesByProbability = ({ elementTypeId, candidates }: { elementTypeId: string; candidates: MasterMove[] }) =>
    sortByProbability({
      elementTypeId,
      candidates: candidates.filter((move) => move.elementTypeId === elementTypeId && move.learnableLevelMinimum === STARTING_LEVEL),
    });
  /** Lv.1 で覚える技の ID。選んだ順に並び、`STARTING_MOVE_COUNT` 個を超えず、重複しない。 */
  const startingMoveIds: string[] = [];
  /**
   * 属性ごとの技の列 [movesByElement] から、各列の先頭から 1 つずつ交互に取って `startingMoveIds` の後ろに足す (副作用)。
   * `startingMoveIds` が [limit] 個に達した後と、すでに入っている技は足さない。
   */
  const takeInTurns = ({ movesByElement, limit }: { movesByElement: MasterMove[][]; limit: number }) => {
    for (let round = 0; movesByElement.some((elementMoves) => round < elementMoves.length); round++) {
      for (const move of movesByElement.map((elementMoves) => elementMoves[round])) {
        if (move && startingMoveIds.length < limit && !startingMoveIds.includes(move.id)) {
          startingMoveIds.push(move.id);
        }
      }
    }
  };
  takeInTurns({
    movesByElement: elementTypeIds.map((elementTypeId) => startingMovesByProbability({ elementTypeId, candidates: moves })),
    limit: Math.min(STARTING_OWN_ELEMENT_MOVE_COUNT, STARTING_MOVE_COUNT),
  });
  takeInTurns({
    movesByElement: [...new Set(fallbackMoves.map((move) => move.elementTypeId))]
      .filter((elementTypeId) => !elementTypeIds.includes(elementTypeId))
      .sort((leftId, rightId) => (elementProbabilities[rightId] ?? 0) - (elementProbabilities[leftId] ?? 0) || leftId.localeCompare(rightId))
      .map((elementTypeId) => startingMovesByProbability({ elementTypeId, candidates: fallbackMoves })),
    limit: STARTING_MOVE_COUNT,
  });

  /** 属性ごとの残りの技 (Lv.1 で取らなかった技) を、レベル帯の下限 → 確率の順に並べ、[category] の技だけを属性の順に交互に並べて返す。 */
  const laterCandidates = ({ category }: { category: "attack" | "support" }) => {
    const byElement = elementTypeIds.map((elementTypeId) =>
      sortByProbability({
        elementTypeId,
        candidates: moves.filter((move) => move.elementTypeId === elementTypeId && move.category === category && !startingMoveIds.includes(move.id)),
      }).sort((left, right) => left.learnableLevelMinimum - right.learnableLevelMinimum),
    );
    const merged: MasterMove[] = [];
    for (let round = 0; byElement.some((elementMoves) => round < elementMoves.length); round++) {
      for (const move of byElement.map((elementMoves) => elementMoves[round])) {
        if (move && !merged.some((candidate) => candidate.id === move.id)) {
          merged.push(move);
        }
      }
    }
    return merged;
  };
  const attackCandidates = laterCandidates({ category: "attack" });
  const supportCandidates = laterCandidates({ category: "support" });
  const laterLearnset: LearnsetEntry[] = [];
  for (let index = 0; attackCandidates.length > 0 || supportCandidates.length > 0; index++) {
    const preferSupport = (index + 1) % SUPPORT_MOVE_INTERVAL === 0;
    const move = (preferSupport ? supportCandidates.shift() ?? attackCandidates.shift() : attackCandidates.shift() ?? supportCandidates.shift())!;
    laterLearnset.push({ moveId: move.id, unlockLevel: Math.max(laterLearnLevel({ index }), move.learnableLevelMinimum) });
  }
  return [
    ...startingMoveIds.map((moveId) => ({ moveId, unlockLevel: STARTING_LEVEL })),
    ...laterLearnset.sort((left, right) => left.unlockLevel - right.unlockLevel),
  ];
}
