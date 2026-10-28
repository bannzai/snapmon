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
  selectElementTypeIds,
  STARTING_MOVE_COUNT,
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
    expect(selectElementTypeIds({ elementProbabilities: { metal: 0.6, glass: 0.9, heat: 0.7, water: 0.2 }, master })).toEqual(["glass", "heat"]);
    expect(selectElementTypeIds({ elementProbabilities: { metal: 0.39, water: 0.1 }, master })).toEqual([]);
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

  it("属性が 1 つなら、その属性の Lv.1 の技を Jev の確率が高い順に 4 つ選ぶ", () => {
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
      { moveId: "paper_1", unlockLevel: 1 },
      { moveId: "paper_1c", unlockLevel: 1 },
      { moveId: "paper_2", unlockLevel: 15 },
      { moveId: "paper_3", unlockLevel: 100 },
    ]);
  });

  it("属性が 2 つなら、Lv.1 は属性の順に交互に 2 つずつ選び、Lv.2 以降は属性ごとにレベル帯ごとの技を開放レベル順に並べる", () => {
    expect(
      buildLearnset({ elementTypeIds: ["heat", "metal"], elementProbabilities: { heat: 0.9, metal: 0.6 }, moveProbabilitiesByElement: {}, moves: master.moves, fallbackMoves: master.moves }),
    ).toEqual([
      { moveId: "heat_1", unlockLevel: 1 },
      { moveId: "metal_1", unlockLevel: 1 },
      { moveId: "heat_1b", unlockLevel: 1 },
      { moveId: "metal_1b", unlockLevel: 1 },
      { moveId: "heat_2", unlockLevel: 15 },
      { moveId: "metal_2", unlockLevel: 15 },
      { moveId: "heat_3", unlockLevel: 100 },
      { moveId: "metal_3", unlockLevel: 100 },
    ]);
  });

  it("その場で作った属性で Lv.1 の技が足りない時は、master の別の属性から当てはまりが高い順に 1 つずつ足す", () => {
    const dynamicMoves = ["custom_wax_1", "custom_wax_2"].map((id, index) => ({
      ...master.moves.find((move) => move.id === `heat_${index + 1}`)!,
      id,
      elementTypeId: "custom_wax",
    }));
    // その場で作った別の属性の技は、このモンスターの definitionIds に入らず端末で引けないため補充に使わない
    const otherDynamicMove = { ...dynamicMoves[0], id: "custom_soap_1", elementTypeId: "custom_soap" };
    const learnset = buildLearnset({
      elementTypeIds: ["custom_wax"],
      elementProbabilities: { custom_soap: 0.39, plastic: 0.3, heat: 0.3, paper: 0.1 },
      moveProbabilitiesByElement: { heat: { heat_1c: 0.6 } },
      moves: [...master.moves, ...dynamicMoves, otherDynamicMove],
      fallbackMoves: master.moves,
    });
    expect(startingMoveIds(learnset)).toEqual(["custom_wax_1", "heat_1c", "plastic_1", "paper_1"]);
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
    expect(startingMoveIds(learnset)).toEqual(["paper_1", "water_1", "cloth_1", "electric_1"]);
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

  it("Lv.2 以降の同じレベル帯に技が 2 つ以上ある時は Jev の確率が高い技を選ぶ", () => {
    const extraMove = { ...master.moves.find((move) => move.id === "heat_2")!, id: "heat_extra" };
    expect(
      buildLearnset({
        elementTypeIds: ["heat"],
        elementProbabilities: { heat: 0.9 },
        moveProbabilitiesByElement: { heat: { heat_2: 0.2, heat_extra: 0.7 } },
        moves: [...master.moves, extraMove],
        fallbackMoves: master.moves,
      })[STARTING_MOVE_COUNT],
    ).toEqual({ moveId: "heat_extra", unlockLevel: 15 });
  });
});
