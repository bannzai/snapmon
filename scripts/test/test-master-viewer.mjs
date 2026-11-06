// docs/master-viewer.js (master の一覧のページの、DOM に触らない処理) のテスト。
// 実行: node --test scripts/test/test-master-viewer.mjs (リポジトリのルートで)。値は実物の assets/master/master.json から取り、テストに写さない
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  DEFAULT_MASTER_URL,
  MASTER_SECTIONS,
  resolveMasterUrl,
  unrenderedKeys,
  multiplierKind,
  isColorHex,
  moveFeedbackLine,
  elementTypeFeedbackLine,
  typeChartCellFeedbackLine,
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
  assert.equal(resolveMasterUrl('https://bannzai.github.io/snapmon/master.html'), DEFAULT_MASTER_URL);
});

test('src はページからの相対で解決する', () => {
  assert.equal(
    resolveMasterUrl('http://localhost:8000/docs/master.html?src=../assets/master/master.json'),
    'http://localhost:8000/assets/master/master.json',
  );
});

test('src の http・https の絶対 URL はそのまま使う', () => {
  assert.equal(
    resolveMasterUrl('https://bannzai.github.io/snapmon/master.html?src=https://example.com/master.json'),
    'https://example.com/master.json',
  );
});

test('src の javascript: と data: は拒否する', () => {
  assert.throws(() => resolveMasterUrl('https://bannzai.github.io/snapmon/master.html?src=javascript:alert(1)'), /javascript:/);
  assert.throws(() => resolveMasterUrl('https://bannzai.github.io/snapmon/master.html?src=data:application/json,{}'), /data:/);
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
    `${move.id} ${move.displayName} ${master.elementTypes.find((candidate) => candidate.id === move.elementTypeId).displayName} 威力 ${move.power} PP ${move.powerPoints} Lv ${move.learnableLevelMinimum}-${move.learnableLevelMaximum}`,
  );
});

test('特殊効果のある技の 1 行は効果の説明と倍率の式を含む', () => {
  const move = master.moves.find((candidate) => candidate.specialEffect);
  assert.ok(moveFeedbackLine(master, move).endsWith(`特殊効果 ${move.specialEffect.summary} 倍率(%) = ${move.specialEffect.power}`));
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
