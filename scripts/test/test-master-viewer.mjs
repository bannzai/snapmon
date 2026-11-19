// docs/master-viewer.js (master の一覧のページの、DOM に触らない処理) のテスト。
// 実行: node --test scripts/test/test-master-viewer.mjs (リポジトリのルートで)。値は実物の assets/master/master.json から取り、テストに写さない
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  DEFAULT_MASTER_URL,
  MASTER_SECTIONS,
  resolveMasterURL,
  unrenderedKeys,
  multiplierKind,
  isColorHex,
  moveFeedbackLine,
  elementTypeFeedbackLine,
  typeChartCellFeedbackLine,
  typeChartElementTypeIDs,
  typeChartMultiplier,
  buildDiff,
} from '../../docs/master-viewer.js';

const master = JSON.parse(readFileSync(new URL('../../assets/master/master.json', import.meta.url), 'utf8'));
const masterHtml = readFileSync(new URL('../../docs/master.html', import.meta.url), 'utf8');

test('master.json のトップレベルのキーはすべてページの表の対象になっている', () => {
  assert.deepEqual(unrenderedKeys(master), []);
});

test('MASTER_SECTIONS の各キーに master.html の描画がある', () => {
  for (const section of MASTER_SECTIONS) {
    assert.match(masterHtml, new RegExp(`\\n  ${section.key}: \\(master\\) =>`), section.key);
  }
});

test('master.json のエフェクトの色はすべて isColorHex を通る', () => {
  for (const effect of master.effects) {
    assert.equal(isColorHex(effect.colorHex), true, effect.id);
  }
});

test('#RRGGBB に似ているが違う形は isColorHex を通らない', () => {
  const [effect] = master.effects;
  assert.equal(isColorHex(`${effect.colorHex};background:url(https://example.com/x)`), false);
  assert.equal(isColorHex(effect.colorHex.slice(1)), false);
  assert.equal(isColorHex(effect.colorHex.slice(0, 4)), false);
  assert.equal(isColorHex(`${effect.colorHex}\n`), false);
  assert.equal(isColorHex('#GGGGGG'), false);
});

test('MASTER_SECTIONS に無いキーは unrenderedKeys が返す', () => {
  assert.deepEqual(unrenderedKeys({ ...master, newKey: [] }), ['newKey']);
});

test('src が無ければ main の master.json を読む', () => {
  assert.equal(resolveMasterURL('https://snapmonster.app/master.html'), DEFAULT_MASTER_URL);
});

test('src はページからの相対で解決する', () => {
  assert.equal(
    resolveMasterURL('http://localhost:8000/docs/master.html?src=../assets/master/master.json'),
    'http://localhost:8000/assets/master/master.json',
  );
});

test('src の http・https の絶対 URL はそのまま使う', () => {
  assert.equal(
    resolveMasterURL('https://snapmonster.app/master.html?src=https://example.com/master.json'),
    'https://example.com/master.json',
  );
});

test('src の javascript: と data: は拒否する', () => {
  assert.throws(() => resolveMasterURL('https://snapmonster.app/master.html?src=javascript:alert(1)'), /javascript:/);
  assert.throws(() => resolveMasterURL('https://snapmonster.app/master.html?src=data:application/json,{}'), /data:/);
});

test('倍率の区分', () => {
  assert.equal(multiplierKind(2), 'strong');
  assert.equal(multiplierKind(0.5), 'weak');
  assert.equal(multiplierKind(1), 'neutral');
});

test('技の 1 行は ID・表示名・属性の表示名・威力・PP・覚えるレベルを含む', () => {
  const move = master.moves.find((candidate) => !candidate.specialEffect);
  assert.equal(
    moveFeedbackLine(master, move),
    `${move.id} ${move.displayName} ${master.elementTypes.find((candidate) => candidate.id === move.elementTypeID).displayName} 威力 ${move.power} PP ${move.powerPoints} Lv ${move.learnableLevelMinimum}-${move.learnableLevelMaximum}`,
  );
});

test('特殊効果のある技の 1 行は効果の説明と倍率の式を含む', () => {
  const move = master.moves.find((candidate) => candidate.specialEffect?.power);
  assert.ok(moveFeedbackLine(master, move).endsWith(`特殊効果 ${move.specialEffect.summary} 倍率(%) = ${move.specialEffect.power}`));
});

test('補助技の 1 行はステータスの変化と回復の式を含み、倍率の式を含まない', () => {
  const statChangeMove = master.moves.find((candidate) => candidate.specialEffect?.opponentStatChanges?.defense);
  const statChangeLine = moveFeedbackLine(master, statChangeMove);
  assert.ok(statChangeLine.endsWith(`特殊効果 ${statChangeMove.specialEffect.summary} 相手の防御(%) += ${statChangeMove.specialEffect.opponentStatChanges.defense}`));
  assert.ok(!statChangeLine.includes('倍率(%)'));
  const recoveryMove = master.moves.find((candidate) => candidate.specialEffect?.selfHitPointsRecovery);
  assert.ok(moveFeedbackLine(master, recoveryMove).endsWith(`回復 = ${recoveryMove.specialEffect.selfHitPointsRecovery}`));
});

test('属性の 1 行', () => {
  const [elementType] = master.elementTypes;
  assert.equal(elementTypeFeedbackLine(elementType), `${elementType.id} ${elementType.displayName} ${elementType.description}`);
});

test('相性表のセルの 1 行は攻撃側と防御側の表示名と倍率を含む', () => {
  const [attacker, defender] = master.elementTypes;
  const multiplier = master.typeChart[attacker.id][defender.id];
  assert.equal(
    typeChartCellFeedbackLine(master, attacker.id, defender.id, multiplier),
    `相性 ${attacker.id} ${attacker.displayName} → ${defender.id} ${defender.displayName} ${multiplier} 倍`,
  );
});

test('相性表は master の属性に無い、その場で作られた属性「料理」の行と列も並べる', () => {
  const elementTypeIDs = typeChartElementTypeIDs(master);
  assert.ok(elementTypeIDs.includes('element_357cac2f'));
  for (const [attackerID, row] of Object.entries(master.typeChart)) {
    assert.ok(elementTypeIDs.includes(attackerID), attackerID);
    for (const defenderID of Object.keys(row)) assert.ok(elementTypeIDs.includes(defenderID), defenderID);
  }
});

test('相性表に並べる属性は master の属性の並びを先頭に保ち、同じ ID を 2 度並べない', () => {
  const elementTypeIDs = typeChartElementTypeIDs(master);
  assert.deepEqual(elementTypeIDs.slice(0, master.elementTypes.length), master.elementTypes.map((elementType) => elementType.id));
  assert.equal(new Set(elementTypeIDs).size, elementTypeIDs.length);
});

test('相性表のキーが master の属性だけなら、並べる属性は master の属性と同じ', () => {
  const elementTypes = [{ id: 'fire' }, { id: 'water' }];
  assert.deepEqual(
    typeChartElementTypeIDs({ elementTypes, typeChart: { water: { fire: 2, water: 0.5 }, fire: { fire: 0.5, water: 0.5 } } }),
    ['fire', 'water'],
  );
  assert.deepEqual(typeChartElementTypeIDs({ elementTypes, typeChart: {} }), ['fire', 'water']);
  assert.deepEqual(typeChartElementTypeIDs({ elementTypes: [], typeChart: {} }), []);
});

test('相性表の行だけ・列だけにある属性も、出てきた順で master の属性の後ろに並べる', () => {
  assert.deepEqual(
    typeChartElementTypeIDs({
      elementTypes: [{ id: 'fire' }],
      typeChart: { fire: { fire: 0.5, element_column: 2 }, element_row: { fire: 2 } },
    }),
    ['fire', 'element_column', 'element_row'],
  );
});

test('相性表の倍率は行か列が無い組を等倍で返し、ある組は表の値を返す', () => {
  const sparseMaster = { typeChart: { fire: { water: 0.5 } } };
  assert.equal(typeChartMultiplier(sparseMaster, 'fire', 'water'), 0.5);
  assert.equal(typeChartMultiplier(sparseMaster, 'fire', 'grass'), 1);
  assert.equal(typeChartMultiplier(sparseMaster, 'grass', 'water'), 1);
  assert.equal(typeChartMultiplier(master, 'element_357cac2f', 'beast'), 2);
  assert.equal(typeChartMultiplier(master, 'water', 'element_357cac2f'), 2);
});

test('master.html の相性表は typeChartElementTypeIDs の属性を並べ、倍率を typeChartMultiplier で引く', () => {
  assert.match(masterHtml, /const elementTypeIDs = typeChartElementTypeIDs\(master\);/);
  assert.doesNotMatch(masterHtml, /typeChart\[attackerID\]\[defenderID\]/);
});

test('書き換えが無ければ差分は null', () => {
  assert.equal(buildDiff(master, { moves: {}, typeChart: {} }), null);
});

test('差分は変えた値だけを技の ID と属性の ID をキーにして返す', () => {
  const [move] = master.moves;
  const [attacker, defender] = master.elementTypes;
  const originalMultiplier = master.typeChart[attacker.id][defender.id];
  assert.deepEqual(
    buildDiff(master, {
      moves: { [move.id]: { power: move.power + 10, powerPoints: move.powerPoints } },
      typeChart: { [attacker.id]: { [defender.id]: originalMultiplier * 2, [attacker.id]: master.typeChart[attacker.id][attacker.id] } },
    }),
    {
      baseVersion: master.version,
      moves: { [move.id]: { power: move.power + 10 } },
      typeChart: { [attacker.id]: { [defender.id]: originalMultiplier * 2 } },
    },
  );
});

test('元の値に戻した項目は差分に含めない', () => {
  const [move] = master.moves;
  assert.equal(buildDiff(master, { moves: { [move.id]: { power: move.power } }, typeChart: {} }), null);
});
