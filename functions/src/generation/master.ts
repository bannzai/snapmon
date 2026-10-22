import type { Firestore } from "firebase-admin/firestore";

// master (`master/{version}`。元の JSON は assets/master/master.json) と、生成時にその場で作った定義 (`definitions/{definitionId}`) の型と読み出し。
// 形は Dart の lib/domain/master/master_data.dart が読む JSON と同じ。

/** 属性の 1 件。 */
export interface MasterElementType {
  /** 属性の識別子。 */
  id: string;
  /** 画面に出す属性の名前。 */
  displayName: string;
  /** その場で作った属性の説明 (Jev の問いに使う)。master の属性は持たない。 */
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
  /** 技の分類 (現在は attack だけ)。 */
  category: string;
  /** 技のエフェクトの識別子。 */
  effectId: string;
  /** 覚えさせてよいレベル帯の下限 (覚える技の一覧の開放レベルに使う)。 */
  learnableLevelMinimum: number;
  /** 覚えさせてよいレベル帯の上限。 */
  learnableLevelMaximum: number;
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
  /** 技のエフェクトの一覧。 */
  effects: { id: string; displayName: string; kind: string; colorHex: string }[];
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

/** その場で作った定義をすべて読む。件数は属性の上限 (ADR 0001 の 24 種) までに収まるため、全件を読む。 */
export async function fetchDynamicDefinitions(firestore: Firestore): Promise<{ id: string; definition: DynamicDefinition }[]> {
  const snapshot = await firestore.collection("definitions").get();
  return snapshot.docs.map((document) => ({ id: document.id, definition: document.data() as DynamicDefinition }));
}
