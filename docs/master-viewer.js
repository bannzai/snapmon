// master.html (master の一覧のページ) のうち、DOM に触らない処理。scripts/test/test-master-viewer.mjs が node で検査する

/**
 * 既定の読み込み元。master の正は assets/master/master.json の 1 つだけにし、docs/ に写しを置かない。
 * Pages の配信の範囲 (main の /docs) の外にあるため、main の raw URL から読む
 */
export const DEFAULT_MASTER_URL =
  'https://raw.githubusercontent.com/bannzai/snapmon/main/assets/master/master.json';

/** ページが表で出す master.json のトップレベルのキーと見出し。並びはページの並び */
export const MASTER_SECTIONS = [
  { key: 'version', title: '版' },
  { key: 'elementTypes', title: '属性' },
  { key: 'typeChart', title: '相性表' },
  { key: 'moves', title: '技' },
  { key: 'effects', title: 'エフェクト' },
  { key: 'statGrades', title: 'ステータスの段階' },
  { key: 'elementSelection', title: '属性の選び方' },
  { key: 'subjectCategories', title: '被写体のカテゴリ' },
];

/**
 * ページの URL (pageHref) から master.json の読み込み元の URL を返す。
 * `src` クエリがあればページからの相対で解決した URL、無ければ DEFAULT_MASTER_URL。
 * 手元で編集した master.json は、リポジトリのルートで配信して `?src=../assets/master/master.json` で開く。
 * 解決した URL が http・https 以外 (`javascript:` 等) の時は throw する。ページは URL をリンクに出すため、
 * 他人が作った `?src=javascript:...` の URL を開いてリンクを押すとページのオリジンでスクリプトが動くのを防ぐ
 */
export function resolveMasterURL(pageHref) {
  const pageURL = new URL(pageHref);
  const src = pageURL.searchParams.get('src');
  if (!src) return DEFAULT_MASTER_URL;
  const masterURL = new URL(src, pageURL);
  if (masterURL.protocol !== 'http:' && masterURL.protocol !== 'https:') {
    throw new Error(`src に http・https 以外の URL は使えません (${masterURL.protocol})`);
  }
  return masterURL.href;
}

/** master.json にあるのに MASTER_SECTIONS に無いキーを返す。ページはこれを警告として出し、黙って落とさない */
export function unrenderedKeys(master) {
  return Object.keys(master).filter((key) => !MASTER_SECTIONS.some((section) => section.key === key));
}

/** 相性表の倍率 (multiplier) を色分けの区分 'strong' (1 より大きい)・'weak' (1 より小さい)・'neutral' にして返す */
export function multiplierKind(multiplier) {
  if (multiplier > 1) return 'strong';
  if (multiplier < 1) return 'weak';
  return 'neutral';
}

/**
 * エフェクトの色 (colorHex) が master.json の形 `#RRGGBB` なら true を返す。
 * `?src=` で他人の JSON も読めるため、この形でない値を CSS に渡さない
 */
export function isColorHex(colorHex) {
  return /^#[0-9a-fA-F]{6}$/.test(colorHex);
}

/** 属性の ID (elementTypeID) の表示名を master.elementTypes から返す。見つからなければ ID をそのまま返す。
 * elementTypes に無い属性を技が指す master でも表を落とさず、どの属性 ID が抜けているかを表で見つけられるようにするため */
export function elementTypeDisplayName(master, elementTypeID) {
  return master.elementTypes.find((elementType) => elementType.id === elementTypeID)?.displayName ?? elementTypeID;
}

/** 技 (move) 1 件をフィードバック向けの 1 行 (例: `metal_1 ブリキパンチ 金属 威力 40 PP 30 Lv 1-30`) にして返す */
export function moveFeedbackLine(master, move) {
  const parts = [
    move.id,
    move.displayName,
    elementTypeDisplayName(master, move.elementTypeID),
    `威力 ${move.power}`,
    `PP ${move.powerPoints}`,
    `Lv ${move.learnableLevelMinimum}-${move.learnableLevelMaximum}`,
  ];
  if (move.specialEffect) {
    // 出力ごとの式 (lib/domain/master/move.dart の MoveSpecialEffect)。攻撃技は威力の倍率、補助技はステータスの変化と回復
    const statNames = { attack: '攻撃', defense: '防御', speed: '素早さ' };
    const { summary, power, selfStatChanges = {}, opponentStatChanges = {}, selfHitPointsRecovery } = move.specialEffect;
    parts.push(
      [
        `特殊効果 ${summary}`,
        ...(power === undefined ? [] : [`倍率(%) = ${power}`]),
        ...Object.entries(selfStatChanges).map(([stat, expression]) => `自分の${statNames[stat] ?? stat}(%) += ${expression}`),
        ...Object.entries(opponentStatChanges).map(([stat, expression]) => `相手の${statNames[stat] ?? stat}(%) += ${expression}`),
        ...(selfHitPointsRecovery === undefined ? [] : [`回復 = ${selfHitPointsRecovery}`]),
      ].join(' '),
    );
  }
  return parts.join(' ');
}

/** 属性 (elementType) 1 件をフィードバック向けの 1 行にして返す */
export function elementTypeFeedbackLine(elementType) {
  return `${elementType.id} ${elementType.displayName} ${elementType.description}`;
}

/** 相性表の 1 セル (攻撃側 attackerID が防御側 defenderID に与える倍率 multiplier) をフィードバック向けの 1 行にして返す */
export function typeChartCellFeedbackLine(master, attackerID, defenderID, multiplier) {
  return `相性 ${attackerID} ${elementTypeDisplayName(master, attackerID)} → ${defenderID} ${elementTypeDisplayName(master, defenderID)} ${multiplier} 倍`;
}

/**
 * ページで書き換えた値 (edits) のうち master と違うものだけを、master.json のキーの形で返す。違いが無ければ null。
 * edits の形: { moves: { [技の ID]: { power?, powerPoints? } }, typeChart: { [攻撃側の属性 ID]: { [防御側の属性 ID]: 倍率 } } }
 * 返す形: { baseVersion: 比べた master の版, moves?: { [技の ID]: { 変えたフィールド: 新しい値 } }, typeChart?: 同上 }。
 * moves は master.json では配列のため、技の ID をキーにしたオブジェクトで返す。元の値に戻した項目は含めない
 */
export function buildDiff(master, edits) {
  const diff = {};
  for (const [moveID, fields] of Object.entries(edits.moves ?? {})) {
    const originalMove = master.moves.find((move) => move.id === moveID);
    if (!originalMove) continue;
    for (const [field, value] of Object.entries(fields)) {
      if (originalMove[field] === value) continue;
      diff.moves ??= {};
      diff.moves[moveID] ??= {};
      diff.moves[moveID][field] = value;
    }
  }
  for (const [attackerID, row] of Object.entries(edits.typeChart ?? {})) {
    for (const [defenderID, value] of Object.entries(row)) {
      if (master.typeChart[attackerID]?.[defenderID] === value) continue;
      diff.typeChart ??= {};
      diff.typeChart[attackerID] ??= {};
      diff.typeChart[attackerID][defenderID] = value;
    }
  }
  return Object.keys(diff).length === 0 ? null : { baseVersion: master.version, ...diff };
}
