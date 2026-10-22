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

/**
 * 属性ごとの技の確率 (Jev の Choice の `probabilities`) から覚える技の一覧を組む。
 * 属性ごとに、技を覚えさせてよいレベル帯の下限 (`learnableLevelMinimum`) ごとに最も確率の高い技を 1 つ選び、その下限を開放レベルにする
 * (master は属性ごとにレベル帯ごとの技を 1 つずつ持ち、その場で作った定義が同じ帯に技を足した時に Choice の結果が効く)。
 * 並びは開放レベル順、同じレベルなら属性の順 (`elementTypeIds` の順)。
 */
export function buildLearnset({
  elementTypeIds,
  moveProbabilitiesByElement,
  moves,
}: {
  elementTypeIds: string[];
  moveProbabilitiesByElement: Record<string, Record<string, number>>;
  moves: MasterMove[];
}): LearnsetEntry[] {
  const learnset: (LearnsetEntry & { elementOrder: number })[] = [];
  for (const [elementOrder, elementTypeId] of elementTypeIds.entries()) {
    const probabilities = moveProbabilitiesByElement[elementTypeId] ?? {};
    const bestMoveByLevel = new Map<number, MasterMove>();
    for (const move of moves.filter((candidate) => candidate.elementTypeId === elementTypeId)) {
      const current = bestMoveByLevel.get(move.learnableLevelMinimum);
      if (!current || (probabilities[move.id] ?? 0) > (probabilities[current.id] ?? 0)) {
        bestMoveByLevel.set(move.learnableLevelMinimum, move);
      }
    }
    for (const [unlockLevel, move] of bestMoveByLevel) {
      learnset.push({ moveId: move.id, unlockLevel, elementOrder });
    }
  }
  return learnset
    .sort((left, right) => left.unlockLevel - right.unlockLevel || left.elementOrder - right.elementOrder)
    .map(({ moveId, unlockLevel }) => ({ moveId, unlockLevel }));
}
