import type { Firestore } from "firebase-admin/firestore";

// master (`master/{version}`。元の JSON は assets/master/master.json) と、生成時にその場で作った定義 (`definitions/{definitionId}`) の型と読み出し。
// 形は Dart の lib/domain/master/master_data.dart が読む JSON と同じ。

/** 属性の 1 件。 */
export interface MasterElementType {
  /** 属性の識別子。 */
  id: string;
  /** 画面に出す属性の名前。 */
  displayName: string;
  /** 属性に当てはまる物の基準 (Jev の問いの criteria に入る)。master の属性は版 1 から持ち、その場で作った属性は Claude の提案から入る。 */
  description?: string;
}

/** 技の 1 件。 */
export interface MasterMove {
  /** 技の識別子。 */
  id: string;
  /** 画面に出す技の名前。 */
  displayName: string;
  /** 技の属性の識別子。 */
  elementTypeId: string;
  /** 威力。 */
  power: number;
  /** PP。 */
  powerPoints: number;
  /** 技の分類。attack (ダメージを与える技) か support (威力 0 で、特殊効果でステータスを変えるか HP を回復する技。master の版 7 から)。 */
  category: string;
  /** 技のエフェクトの識別子。 */
  effectId: string;
  /** 覚えさせてよいレベル帯の下限 (覚える技の一覧の開放レベルに使う)。 */
  learnableLevelMinimum: number;
  /** 覚えさせてよいレベル帯の上限。 */
  learnableLevelMaximum: number;
  /**
   * 技の特殊効果。数値の出力は式 (文法は documents/game-rules.md「技の式」、検査は src/move_expression.ts) を持つ。
   * `power` は攻撃技の威力の倍率 (%)、`selfStatChanges`・`opponentStatChanges` は補助技が自分・相手のステータス (attack・defense・speed) の倍率 (%) に足す値、
   * `selfHitPointsRecovery` は補助技が自分の HP を回復する量。
   * 版 9 (#224) から、値で書く効果を持つ: `selfStatusConditions`・`opponentStatusConditions` (付ける状態と確率)、`curesSelfStatusConditions` (自分の状態の解除)、
   * `fieldEffect` (フィールドの効果)、`selfDestructs` (自爆)、`oneHitKnockout` (一撃必殺)、`sureHit` (必中)。状態・フィールドの名前は端末の列挙 (lib/domain/battle/status_condition.dart) が正。
   * `summary` は技の枠に出す短い説明、`rule` はバトルのログと技の詳細に出す効果の規則の説明。計算は端末のバトル (lib/domain/battle/battle_engine.dart) が行う。
   * `rationale` は、この技にこの効果を付けた根拠 (技の名前の物の性質と効果の働き方の結びつき)。
   */
  specialEffect?: {
    power?: string;
    selfStatChanges?: Partial<Record<"attack" | "defense" | "speed", string>>;
    opponentStatChanges?: Partial<Record<"attack" | "defense" | "speed", string>>;
    selfHitPointsRecovery?: string;
    selfStatusConditions?: { kind: string; chancePercent: number }[];
    opponentStatusConditions?: { kind: string; chancePercent: number }[];
    curesSelfStatusConditions?: boolean;
    fieldEffect?: string;
    selfDestructs?: boolean;
    oneHitKnockout?: boolean;
    sureHit?: boolean;
    summary: string;
    rule: string;
    rationale?: string;
  };
  /** 命中率 (%)。無ければ 100 (版 8 までの技)。 */
  accuracy?: number;
  /** 先制の度合い。大きい技が素早さに関係なく先に出る。無ければ 0。 */
  priority?: number;
  /**
   * この技がこの属性・この名前である根拠。技・効果を足す・見直す時に参照する保守のための値で、ユーザーには見せず、生成・バトルでも読まない
   * (documents/game-rules.md「技の根拠」)。master の版 4 より前の版と、版 4 より前にその場で作った技は持たない。
   */
  rationale?: string;
}

/** ステータスの段階と種族値の対応。 */
export interface MasterStatGrade {
  /** 段階の識別子 (Jev の Score の段階の名前)。 */
  id: string;
  /** 画面・文書に出す段階の名前。 */
  displayName: string;
  /** この段階の種族値。 */
  baseStat: number;
}

/** 物の分類 (同じ被写体の判定の候補の絞り込みに使う)。 */
export interface MasterSubjectCategory {
  /** 分類の識別子。 */
  id: string;
  /** 画面・文書に出す分類の名前。 */
  displayName: string;
  /** Jev の Choice の選択肢の説明。 */
  description: string;
}

/** master の 1 つの版 (`master/{version}`)。 */
export interface Master {
  /** 版番号。 */
  version: number;
  /** 属性の一覧。 */
  elementTypes: MasterElementType[];
  /** 相性表。 */
  typeChart: Record<string, Record<string, number>>;
  /** 技の一覧。 */
  moves: MasterMove[];
  /**
   * 技のエフェクトの一覧。`kind` が `spriteSheet` のエフェクトは `spriteSheet` (端末に同梱したシートの名前) と `pixelfxId` (素材の ID。
   * scripts/move_effects/generate_move_effect_sprite_sheets.sh が書き出しに使う) を持つ。
   */
  effects: { id: string; displayName: string; kind: string; colorHex: string; spriteSheet?: string; pixelfxId?: string }[];
  /** ステータスの段階。 */
  statGrades: MasterStatGrade[];
  /** 属性を選ぶ規則。 */
  elementSelection: { probabilityThreshold: number; maximumCount: number };
  /** 物の分類。 */
  subjectCategories: MasterSubjectCategory[];
}

/** その場で作った定義 (`definitions/{definitionId}`)。1 件の属性と、その属性の技を持つ。 */
export interface DynamicDefinition {
  /** 定義の版 (形を変えた時に上げる)。 */
  version: number;
  /** 属性 (1 件)。 */
  elementTypes: MasterElementType[];
  /** その属性の技。 */
  moves: MasterMove[];
}

/** 最新の版の master を読む。投入された版が無ければ throw する (master が無いと何も判定できないため)。 */
export async function fetchLatestMaster(firestore: Firestore): Promise<Master> {
  const snapshot = await firestore.collection("master").orderBy("version", "desc").limit(1).get();
  if (snapshot.empty) {
    throw new Error("master が投入されていません (deploy-functions.yml の master_file で投入する)");
  }
  return snapshot.docs[0].data() as Master;
}

/** 指定した版の master (`master/{version}`) を読む。無ければ throw する (投入済みの版は消さないため、無いのは不整合)。 */
export async function fetchMaster({ firestore, version }: { firestore: Firestore; version: number }): Promise<Master> {
  const snapshot = await firestore.doc(`master/${version}`).get();
  if (!snapshot.exists) {
    throw new Error(`master の版 ${version} がありません`);
  }
  return snapshot.data() as Master;
}

/** その場で作った定義をすべて読む。件数は属性の上限 (pipeline.ts の `ELEMENT_TYPE_LIMIT`) までに収まるため、全件を読む。 */
export async function fetchDynamicDefinitions(firestore: Firestore): Promise<{ id: string; definition: DynamicDefinition }[]> {
  const snapshot = await firestore.collection("definitions").get();
  return snapshot.docs.map((document) => ({ id: document.id, definition: document.data() as DynamicDefinition }));
}
