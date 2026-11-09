import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { learnableMoves, type Master } from "../../src/generation/master";
import { findModerationViolation } from "../../src/generation/moderation";
import {
  baseStatsFromStatGrades,
  buildLearnset,
  fnv1a32,
  individualValuesFromDescription,
  LATER_ATTACK_MOVE_COUNT,
  LATER_SUPPORT_MOVE_COUNT,
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
    expect(individualValuesFromDescription("赤い陶器のマグカップ。手のひらほどの大きさで硬い")).toEqual({ hitPoints: 1, attack: 5, defense: 22, speed: 25, accuracy: 17 });
  });

  it("段階から種族値を引く", () => {
    expect(baseStatsFromStatGrades({ statGradeIds: { hitPoints: "medium", attack: "low", defense: "veryHigh", speed: "veryLow", accuracy: "high" }, master })).toEqual({
      hitPoints: 80,
      attack: 60,
      defense: 120,
      speed: 40,
      accuracy: 100,
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
  const moveOf = (moveId: string) => master.moves.find((move) => move.id === moveId)!;
  const replacedMoveIds = new Set(master.moves.flatMap((move) => (move.replacesMoveId ? [move.replacesMoveId] : [])));
  const descriptions = [...Array(50).keys()].map((index) => `見本の被写体 ${index}。手のひらほどの大きさ`);

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

  it("learnableMoves は別の技の replacesMoveId が指す補助技だけを除く", () => {
    const moveIds = learnableMoves(master.moves).map((move) => move.id);
    // 版 11 で攻撃技 paper_a1 に置き換えた補助技は除き、置き換えていない補助技 paper_s3 (回復) と置き換えた側の paper_a1 は残す
    expect(moveIds).not.toContain("paper_s1");
    expect(moveIds).toContain("paper_s3");
    expect(moveIds).toContain("paper_a1");
    expect(learnableMoves(master.moves)).toHaveLength(master.moves.length - replacedMoveIds.size);
  });

  it("属性が 1 つなら、Lv.1 はその属性の技を Jev の確率が高い順に 2 つと別の属性の技 2 つ、Lv.2 以降は攻撃技と補助技を決まった数だけ覚える", () => {
    const learnset = buildLearnset({
      elementTypeIds: ["paper"],
      elementProbabilities: { paper: 0.9 },
      moveProbabilitiesByElement: { paper: { paper_1d: 0.4, paper_1b: 0.3, paper_1: 0.2, paper_1c: 0.1 } },
      moves: master.moves,
      fallbackMoves: master.moves,
      subjectDescriptionText: descriptions[0],
    });
    const starting = startingMoveIds(learnset);
    expect(starting.slice(0, STARTING_OWN_ELEMENT_MOVE_COUNT)).toEqual(["paper_1d", "paper_1b"]);
    for (const moveId of starting.slice(STARTING_OWN_ELEMENT_MOVE_COUNT)) {
      expect(moveOf(moveId).elementTypeId).not.toBe("paper");
      expect(moveOf(moveId).learnableLevelMinimum).toBe(1);
    }
    const later = learnset.slice(STARTING_MOVE_COUNT).map((entry) => moveOf(entry.moveId));
    expect(later.every((move) => move.elementTypeId === "paper")).toBe(true);
    expect(later.filter((move) => move.category === "attack")).toHaveLength(LATER_ATTACK_MOVE_COUNT);
    expect(later.filter((move) => move.category === "support")).toHaveLength(LATER_SUPPORT_MOVE_COUNT);
  });

  it("属性が 2 つなら、Lv.1 は属性ごとに 1 つずつと別の属性の技 2 つ、Lv.2 以降は 2 つの属性の技を覚え、重複せず開放レベルが単調に増える", () => {
    const learnset = buildLearnset({
      elementTypeIds: ["fire", "steel"],
      elementProbabilities: { fire: 0.9, steel: 0.6 },
      moveProbabilitiesByElement: {},
      moves: master.moves,
      fallbackMoves: master.moves,
      subjectDescriptionText: descriptions[0],
    });
    expect(startingMoveIds(learnset).slice(0, STARTING_OWN_ELEMENT_MOVE_COUNT).map((moveId) => moveOf(moveId).elementTypeId)).toEqual(["fire", "steel"]);
    const laterElementTypeIds = new Set(learnset.slice(STARTING_MOVE_COUNT).map((entry) => moveOf(entry.moveId).elementTypeId));
    expect([...laterElementTypeIds].sort()).toEqual(["fire", "steel"]);
    expect(learnset).toHaveLength(STARTING_MOVE_COUNT + LATER_ATTACK_MOVE_COUNT + LATER_SUPPORT_MOVE_COUNT);
    expect(new Set(learnset.map((entry) => entry.moveId)).size).toBe(learnset.length);
    for (const [index, entry] of learnset.entries()) {
      expect(entry.unlockLevel, entry.moveId).toBeGreaterThanOrEqual(moveOf(entry.moveId).learnableLevelMinimum);
      if (index > 0) {
        expect(entry.unlockLevel).toBeGreaterThanOrEqual(learnset[index - 1].unlockLevel);
      }
    }
  });

  it("同じ属性で別の写真から生まれたモンスターは、覚える技の組み合わせが互いに異なる (#257)", () => {
    for (const elementType of master.elementTypes) {
      const moveIdSets = descriptions.map((subjectDescriptionText) =>
        buildLearnset({
          elementTypeIds: [elementType.id],
          elementProbabilities: { [elementType.id]: 0.9 },
          moveProbabilitiesByElement: {},
          moves: master.moves,
          fallbackMoves: master.moves,
          subjectDescriptionText,
        })
          .map((entry) => entry.moveId)
          .sort()
          .join(","),
      );
      expect(new Set(moveIdSets).size, elementType.id).toBe(descriptions.length);
    }
  });

  it("同じ説明文と同じ判定からは同じ一覧になる (生成の再試行で変わらない)", () => {
    const build = () =>
      buildLearnset({
        elementTypeIds: ["water", "ice"],
        elementProbabilities: { water: 0.8, ice: 0.7, wind: 0.2 },
        moveProbabilitiesByElement: { water: { water_1b: 0.3 } },
        moves: master.moves,
        fallbackMoves: master.moves,
        subjectDescriptionText: descriptions[3],
      });
    expect(build()).toEqual(build());
  });

  it("どの属性の組でも、置き換えられた補助技を覚えず、開放の新しい 4 つ (技の枠) に攻撃技が 2 つ以上残る", () => {
    for (const first of master.elementTypes) {
      for (const second of master.elementTypes) {
        const elementTypeIds = first.id === second.id ? [first.id] : [first.id, second.id];
        for (const subjectDescriptionText of descriptions.slice(0, 3)) {
          const learnset = buildLearnset({
            elementTypeIds,
            elementProbabilities: {},
            moveProbabilitiesByElement: {},
            moves: master.moves,
            fallbackMoves: master.moves,
            subjectDescriptionText,
          });
          expect(learnset.filter((entry) => replacedMoveIds.has(entry.moveId)), elementTypeIds.join(",")).toEqual([]);
          for (let end = STARTING_MOVE_COUNT; end <= learnset.length; end++) {
            const equipped = learnset.slice(end - STARTING_MOVE_COUNT, end);
            expect(equipped.filter((entry) => moveOf(entry.moveId).category === "attack").length, `${elementTypeIds.join(",")} の ${end} 番目まで`).toBeGreaterThanOrEqual(2);
          }
        }
      }
    }
  });

  it("交換不可を付ける技を Lv.100 未満で覚えられる (#257)", () => {
    for (const elementType of master.elementTypes) {
      const switchBlockingMoves = learnableMoves(master.moves).filter(
        (move) => move.elementTypeId === elementType.id && move.specialEffect?.opponentStatusConditions?.some((condition) => condition.kind === "switchBlocked"),
      );
      expect(switchBlockingMoves.map((move) => move.category), elementType.id).toEqual(["attack"]);
      const learnset = buildLearnset({
        elementTypeIds: [elementType.id],
        elementProbabilities: { [elementType.id]: 0.9 },
        moveProbabilitiesByElement: { [elementType.id]: { [switchBlockingMoves[0].id]: 0.9 } },
        moves: master.moves,
        fallbackMoves: master.moves,
        subjectDescriptionText: descriptions[0],
      });
      expect(learnset.find((entry) => entry.moveId === switchBlockingMoves[0].id)?.unlockLevel, elementType.id).toBeLessThan(100);
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
      elementProbabilities: { custom_soap: 0.39, machine: 0.35, fire: 0.3, paper: 0.1 },
      moveProbabilitiesByElement: { fire: { fire_1c: 0.6 }, machine: { machine_1b: 0.5 }, paper: { paper_1d: 0.5 } },
      moves: [...master.moves, ...dynamicMoves, otherDynamicMove],
      fallbackMoves: master.moves,
      subjectDescriptionText: descriptions[0],
    });
    expect(startingMoveIds(learnset)).toEqual(["custom_wax_1", "machine_1b", "fire_1c", "paper_1d"]);
    expect(learnset.slice(STARTING_MOVE_COUNT)).toEqual([{ moveId: "custom_wax_2", unlockLevel: 15 }]);
  });

  it("master の属性に Lv.1 の技が 1 つしか無い版でも、別の属性で埋めて重複の無い 4 つにする", () => {
    const oneMovePerBand = master.moves.filter((move) => /_\d$/.test(move.id));
    const moveIds = startingMoveIds(
      buildLearnset({
        elementTypeIds: ["paper"],
        elementProbabilities: { paper: 0.9, water: 0.5 },
        moveProbabilitiesByElement: {},
        moves: oneMovePerBand,
        fallbackMoves: oneMovePerBand,
        subjectDescriptionText: descriptions[0],
      }),
    );
    expect(moveIds.slice(0, 2)).toEqual(["paper_1", "water_1"]);
    expect(moveIds).toHaveLength(STARTING_MOVE_COUNT);
    expect(new Set(moveIds).size).toBe(STARTING_MOVE_COUNT);
  });

  it("どの属性の組でも Lv.1 の技は 4 つで重複が無い", () => {
    for (const first of master.elementTypes) {
      for (const second of master.elementTypes) {
        const elementTypeIds = first.id === second.id ? [first.id] : [first.id, second.id];
        const moveIds = startingMoveIds(
          buildLearnset({
            elementTypeIds,
            elementProbabilities: {},
            moveProbabilitiesByElement: {},
            moves: master.moves,
            fallbackMoves: master.moves,
            subjectDescriptionText: descriptions[0],
          }),
        );
        expect(moveIds, elementTypeIds.join(",")).toHaveLength(STARTING_MOVE_COUNT);
        expect(new Set(moveIds).size).toBe(STARTING_MOVE_COUNT);
      }
    }
  });

  it("Lv.2 以降は Jev の確率が高い技から選び、同じレベル帯では確率が高い技から先に覚える", () => {
    const extraMove = { ...master.moves.find((move) => move.id === "fire_2")!, id: "fire_extra" };
    const learnset = buildLearnset({
      elementTypeIds: ["fire"],
      elementProbabilities: { fire: 0.9 },
      moveProbabilitiesByElement: { fire: { fire_2: 0.2, fire_extra: 0.7 } },
      moves: [...master.moves, extraMove],
      fallbackMoves: master.moves,
      subjectDescriptionText: descriptions[0],
    });
    const indexOf = (moveId: string) => learnset.findIndex((entry) => entry.moveId === moveId);
    expect(indexOf("fire_extra")).toBeGreaterThan(0);
    expect(indexOf("fire_extra")).toBeLessThan(indexOf("fire_2"));
  });
});
