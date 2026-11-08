import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import type { Master } from "../../src/generation/master";
import { findModerationViolation } from "../../src/generation/moderation";
import {
  baseStatsFromStatGrades,
  buildLearnset,
  fnv1a32,
  individualValuesFromDescription,
  laterLearnLevel,
  selectElementTypeIds,
  STARTING_MOVE_COUNT,
  STARTING_OWN_ELEMENT_MOVE_COUNT,
} from "../../src/generation/monster_stats";

const master = JSON.parse(readFileSync(path.join(__dirname, "..", "..", "..", "assets", "master", "master.json"), "utf8")) as Master;

describe("Dart の計算 (lib/domain/) と同じ値", () => {
  it("FNV-1a は参照値と一致する (test/domain/monster/stat_calculation_test.dart と同じ値)", () => {
    expect(fnv1a32("")).toBe(0x811c9dc5);
    expect(fnv1a32("a")).toBe(0xe40c292c);
    expect(fnv1a32("foobar")).toBe(0xbf9cf968);
  });

  it("同じ説明文からは Dart のテストと同じ個体値になる", () => {
    expect(individualValuesFromDescription("赤い陶器のマグカップ。手のひらほどの大きさで硬い")).toEqual({ hitPoints: 1, attack: 5, defense: 22, speed: 25 });
  });

  it("段階から種族値を引く", () => {
    expect(baseStatsFromStatGrades({ statGradeIds: { hitPoints: "medium", attack: "low", defense: "veryHigh", speed: "veryLow" }, master })).toEqual({
      hitPoints: 80,
      attack: 60,
      defense: 120,
      speed: 40,
    });
  });

  it("個体値は 0〜31 に収まる", () => {
    for (let index = 0; index < 200; index++) {
      for (const value of Object.values(individualValuesFromDescription(`見本 ${index}`))) {
        expect(value).toBeGreaterThanOrEqual(0);
        expect(value).toBeLessThanOrEqual(31);
      }
    }
  });
});

describe("selectElementTypeIds", () => {
  it("閾値以上を確率の高い順に上限まで選び、無ければ空を返す", () => {
    expect(selectElementTypeIds({ elementProbabilities: { steel: 0.6, light: 0.9, fire: 0.7, water: 0.2 }, master })).toEqual(["light", "fire"]);
    expect(selectElementTypeIds({ elementProbabilities: { steel: 0.49, water: 0.1 }, master })).toEqual([]);
  });
});

describe("buildLearnset", () => {
  const startingMoveIds = (learnset: { moveId: string; unlockLevel: number }[]) => learnset.filter((entry) => entry.unlockLevel === 1).map((entry) => entry.moveId);

  it("master の全属性が Lv.1 の帯に STARTING_MOVE_COUNT 個以上の技を持つ", () => {
    for (const elementType of master.elementTypes) {
      expect(
        master.moves.filter((move) => move.elementTypeId === elementType.id && move.learnableLevelMinimum === 1).length,
        elementType.id,
      ).toBeGreaterThanOrEqual(STARTING_MOVE_COUNT);
    }
  });

  it("master の技の名前は禁止語・他社の名称に当たらない", () => {
    for (const move of master.moves) {
      expect(findModerationViolation(move.displayName), move.id).toBeUndefined();
    }
  });

  it("Lv.2 以降に技を覚えるレベルは 2・3、以降 2 と 3 を交互に足したレベル", () => {
    expect([...Array(10).keys()].map((index) => laterLearnLevel({ index }))).toEqual([2, 3, 5, 8, 10, 13, 15, 18, 20, 23]);
  });

  it("属性が 1 つなら、Lv.1 はその属性の技を Jev の確率が高い順に 2 つと別の属性の技 2 つ、Lv.2 以降は残りの技を攻撃 2 つに補助 1 つの間隔で覚える", () => {
    const learnset = buildLearnset({
      elementTypeIds: ["paper"],
      elementProbabilities: { paper: 0.9 },
      moveProbabilitiesByElement: { paper: { paper_1d: 0.4, paper_1b: 0.3, paper_1: 0.2, paper_1c: 0.1 } },
      moves: master.moves,
      fallbackMoves: master.moves,
    });
    expect(learnset).toEqual([
      { moveId: "paper_1d", unlockLevel: 1 },
      { moveId: "paper_1b", unlockLevel: 1 },
      // 別の属性は当てはまりの確率が同じ (0) なので ID 順
      { moveId: "beast_1", unlockLevel: 1 },
      { moveId: "bird_1", unlockLevel: 1 },
      { moveId: "paper_1", unlockLevel: 2 },
      { moveId: "paper_1c", unlockLevel: 3 },
      { moveId: "paper_s1", unlockLevel: 5 },
      { moveId: "paper_1e", unlockLevel: 8 },
      { moveId: "paper_1f", unlockLevel: 10 },
      { moveId: "paper_s2", unlockLevel: 13 },
      { moveId: "paper_1g", unlockLevel: 15 },
      { moveId: "paper_p1", unlockLevel: 18 },
      { moveId: "paper_s3", unlockLevel: 20 },
      { moveId: "paper_2", unlockLevel: 23 },
      { moveId: "paper_2b", unlockLevel: 25 },
      { moveId: "paper_s4", unlockLevel: 28 },
      { moveId: "paper_2c", unlockLevel: 30 },
      { moveId: "paper_d1", unlockLevel: 33 },
      { moveId: "paper_s5", unlockLevel: 35 },
      { moveId: "paper_s6", unlockLevel: 43 },
      // 版 10 の交換不可にする補助技 (#239)
      { moveId: "paper_s7", unlockLevel: 45 },
      // レベル帯の下限 (100) が覚える順のレベルより高い技は、下限で覚える
      { moveId: "paper_3", unlockLevel: 100 },
      { moveId: "paper_k1", unlockLevel: 100 },
    ]);
  });

  it("属性が 2 つなら、Lv.1 は属性ごとに 1 つずつと別の属性の技 2 つ、Lv.2 以降は 2 つの属性の技を交互に覚える", () => {
    const learnset = buildLearnset({
      elementTypeIds: ["fire", "steel"],
      elementProbabilities: { fire: 0.9, steel: 0.6 },
      moveProbabilitiesByElement: {},
      moves: master.moves,
      fallbackMoves: master.moves,
    });
    expect(startingMoveIds(learnset)).toEqual(["fire_1", "steel_1", "beast_1", "bird_1"]);
    expect(learnset.slice(STARTING_MOVE_COUNT, STARTING_MOVE_COUNT + 6)).toEqual([
      { moveId: "fire_1b", unlockLevel: 2 },
      { moveId: "steel_1b", unlockLevel: 3 },
      { moveId: "fire_s1", unlockLevel: 5 },
      { moveId: "fire_1c", unlockLevel: 8 },
      { moveId: "steel_1c", unlockLevel: 10 },
      { moveId: "steel_s1", unlockLevel: 13 },
    ]);
    // 2 属性の全ての技を覚え、重複しない
    const ownMoveCount = master.moves.filter((move) => move.elementTypeId === "fire" || move.elementTypeId === "steel").length;
    expect(learnset).toHaveLength(ownMoveCount + STARTING_MOVE_COUNT - STARTING_OWN_ELEMENT_MOVE_COUNT);
    expect(new Set(learnset.map((entry) => entry.moveId)).size).toBe(learnset.length);
    // 開放レベルは単調に増え、レベル帯の下限を下回らない
    for (const [index, entry] of learnset.entries()) {
      const move = master.moves.find((candidate) => candidate.id === entry.moveId)!;
      expect(entry.unlockLevel, entry.moveId).toBeGreaterThanOrEqual(move.learnableLevelMinimum);
      if (index > 0) {
        expect(entry.unlockLevel).toBeGreaterThanOrEqual(learnset[index - 1].unlockLevel);
      }
    }
  });

  it("どの属性の組でも、開放の新しい 4 つ (技の枠) に攻撃技が 2 つ以上残る", () => {
    const categoryOf = (moveId: string) => master.moves.find((move) => move.id === moveId)!.category;
    for (const first of master.elementTypes) {
      for (const second of master.elementTypes) {
        const elementTypeIds = first.id === second.id ? [first.id] : [first.id, second.id];
        const learnset = buildLearnset({ elementTypeIds, elementProbabilities: {}, moveProbabilitiesByElement: {}, moves: master.moves, fallbackMoves: master.moves });
        for (let end = STARTING_MOVE_COUNT; end <= learnset.length; end++) {
          const equipped = learnset.slice(end - STARTING_MOVE_COUNT, end);
          expect(equipped.filter((entry) => categoryOf(entry.moveId) === "attack").length, `${elementTypeIds.join(",")} の ${end} 番目まで`).toBeGreaterThanOrEqual(2);
        }
      }
    }
  });

  it("その場で作った属性で Lv.1 の技が足りない時は、master の別の属性から当てはまりが高い順に 1 つずつ足す", () => {
    const dynamicMoves = ["custom_wax_1", "custom_wax_2"].map((id, index) => ({
      ...master.moves.find((move) => move.id === `fire_${index + 1}`)!,
      id,
      elementTypeId: "custom_wax",
    }));
    // その場で作った別の属性の技は、このモンスターの definitionIds に入らず端末で引けないため補充に使わない
    const otherDynamicMove = { ...dynamicMoves[0], id: "custom_soap_1", elementTypeId: "custom_soap" };
    const learnset = buildLearnset({
      elementTypeIds: ["custom_wax"],
      elementProbabilities: { custom_soap: 0.39, machine: 0.3, fire: 0.3, paper: 0.1 },
      moveProbabilitiesByElement: { fire: { fire_1c: 0.6 } },
      moves: [...master.moves, ...dynamicMoves, otherDynamicMove],
      fallbackMoves: master.moves,
    });
    expect(startingMoveIds(learnset)).toEqual(["custom_wax_1", "fire_1c", "machine_1", "paper_1"]);
    expect(learnset.slice(STARTING_MOVE_COUNT)).toEqual([{ moveId: "custom_wax_2", unlockLevel: 15 }]);
  });

  it("master の属性に Lv.1 の技が 1 つしか無い版でも、別の属性で埋めて重複の無い 4 つにする", () => {
    const oneMovePerBand = master.moves.filter((move) => /_\d$/.test(move.id));
    const learnset = buildLearnset({
      elementTypeIds: ["paper"],
      elementProbabilities: { paper: 0.9, water: 0.5 },
      moveProbabilitiesByElement: {},
      moves: oneMovePerBand,
      fallbackMoves: oneMovePerBand,
    });
    expect(startingMoveIds(learnset)).toEqual(["paper_1", "water_1", "beast_1", "bird_1"]);
  });

  it("どの属性の組でも Lv.1 の技は 4 つで重複が無い", () => {
    for (const first of master.elementTypes) {
      for (const second of master.elementTypes) {
        const elementTypeIds = first.id === second.id ? [first.id] : [first.id, second.id];
        const moveIds = startingMoveIds(
          buildLearnset({ elementTypeIds, elementProbabilities: {}, moveProbabilitiesByElement: {}, moves: master.moves, fallbackMoves: master.moves }),
        );
        expect(moveIds, elementTypeIds.join(",")).toHaveLength(STARTING_MOVE_COUNT);
        expect(new Set(moveIds).size).toBe(STARTING_MOVE_COUNT);
      }
    }
  });

  it("Lv.2 以降の同じレベル帯の技は Jev の確率が高い技から先に覚える", () => {
    const extraMove = { ...master.moves.find((move) => move.id === "fire_2")!, id: "fire_extra" };
    const learnset = buildLearnset({
      elementTypeIds: ["fire"],
      elementProbabilities: { fire: 0.9 },
      moveProbabilitiesByElement: { fire: { fire_2: 0.2, fire_extra: 0.7 } },
      moves: [...master.moves, extraMove],
      fallbackMoves: master.moves,
    });
    const indexOf = (moveId: string) => learnset.findIndex((entry) => entry.moveId === moveId);
    expect(indexOf("fire_extra")).toBeLessThan(indexOf("fire_2"));
    expect(indexOf("fire_2")).toBeLessThan(indexOf("fire_2b"));
  });
});
