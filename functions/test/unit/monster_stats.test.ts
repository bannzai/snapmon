import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import type { Master } from "../../src/generation/master";
import { baseStatsFromStatGrades, buildLearnset, fnv1a32, individualValuesFromDescription, selectElementTypeIds } from "../../src/generation/monster_stats";

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
  it("属性ごとにレベル帯ごとの技を開放レベル順に並べる", () => {
    expect(buildLearnset({ elementTypeIds: ["heat", "metal"], moveProbabilitiesByElement: {}, moves: master.moves })).toEqual([
      { moveId: "heat_1", unlockLevel: 1 },
      { moveId: "metal_1", unlockLevel: 1 },
      { moveId: "heat_2", unlockLevel: 15 },
      { moveId: "metal_2", unlockLevel: 15 },
      { moveId: "heat_3", unlockLevel: 100 },
      { moveId: "metal_3", unlockLevel: 100 },
    ]);
  });

  it("同じレベル帯に技が 2 つ以上ある時は Jev の確率が高い技を選ぶ", () => {
    const extraMove = { ...master.moves.find((move) => move.id === "heat_1")!, id: "heat_extra" };
    expect(
      buildLearnset({ elementTypeIds: ["heat"], moveProbabilitiesByElement: { heat: { heat_1: 0.2, heat_extra: 0.7 } }, moves: [...master.moves, extraMove] })[0],
    ).toEqual({ moveId: "heat_extra", unlockLevel: 1 });
  });
});
