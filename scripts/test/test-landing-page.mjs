// docs/index.html (紹介ページ) が、外から決まった URL で開かれ続けることと、リンク・画像の宛先が切れていないことのテスト。
// 実行: node --test scripts/test/test-landing-page.mjs (リポジトリのルートで)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const docsDirectoryURL = new URL('../../docs/', import.meta.url);
const landingPageHTML = readFileSync(new URL('index.html', docsDirectoryURL), 'utf8');

// 紹介ページを公開している URL。GitHub Pages の独自ドメイン (docs/CNAME) と同じ
const LANDING_PAGE_URL = 'https://snapmonster.app/';
// 「今すぐ遊ぶ」の宛先 (Web 版)。https://play.snapmonster.app/ は 2026-11-18T05:43Z の時点で証明書のエラー (curl の exit 60) で
// 200 を返さないため、Firebase Hosting の既定のドメインを指す (issue #362 の「200 を返さなければ snapmon-prod.web.app」)
const WEB_APP_URL = 'https://snapmon-prod.web.app/';

/** landingPageHTML の中の、tagName の開始タグの文字列をすべて返す。 */
function openingTags({ tagName }) {
  return landingPageHTML.match(new RegExp(`<${tagName}\\b[^>]*>`, 'g')) ?? [];
}

/** 開始タグの文字列 tag の、attributeName の属性の値を返す。属性が無ければ undefined。 */
function attributeValue({ tag, attributeName }) {
  return tag.match(new RegExp(`\\s${attributeName}="([^"]*)"`))?.[1];
}

/** landingPageHTML の中の、すべての a 要素の href の値。 */
const linkHrefs = openingTags({ tagName: 'a' }).map((tag) => attributeValue({ tag, attributeName: 'href' }));

test('docs/CNAME の独自ドメインと紹介ページの canonical が同じ', () => {
  assert.equal(`https://${readFileSync(new URL('CNAME', docsDirectoryURL), 'utf8').trim()}/`, LANDING_PAGE_URL);
  assert.ok(landingPageHTML.includes(`<link rel="canonical" href="${LANDING_PAGE_URL}">`));
});

test('SNS のカードの URL と画像が紹介ページのドメインを指し、画像のファイルがある', () => {
  assert.ok(landingPageHTML.includes(`<meta property="og:url" content="${LANDING_PAGE_URL}">`));
  for (const property of ['property="og:image"', 'name="twitter:image"']) {
    assert.ok(landingPageHTML.includes(`<meta ${property} content="${LANDING_PAGE_URL}og.png">`), property);
  }
  assert.ok(existsSync(new URL('og.png', docsDirectoryURL)));
});

test('App Store Connect に登録したサポート URL (/#support) の位置にサポートの節がある', () => {
  assert.equal(openingTags({ tagName: 'section' }).filter((tag) => attributeValue({ tag, attributeName: 'id' }) === 'support').length, 1);
});

test('サポートの節にメールの連絡先がある', () => {
  assert.match(
    landingPageHTML.slice(landingPageHTML.indexOf('<section id="support"'), landingPageHTML.indexOf('<section id="documents"')),
    /<a href="mailto:[^"@]+@[^"@]+">/,
  );
});

test('利用規約・プライバシーポリシー・アカウントの削除の案内へ、公開するファイルがある相対パスでリンクしている', () => {
  for (const pageName of ['Terms', 'PrivacyPolicy', 'AccountDeletion']) {
    assert.ok(linkHrefs.includes(`./${pageName}`), pageName);
    assert.ok(existsSync(new URL(`${pageName}.md`, docsDirectoryURL)), pageName);
  }
});

test('「今すぐ遊ぶ」のリンクがあり、すべて Web 版を指す', () => {
  const playLinkTags = openingTags({ tagName: 'a' }).filter((tag) => /\sdata-play[\s>]/.test(tag));
  assert.ok(playLinkTags.length >= 1);
  for (const tag of playLinkTags) {
    assert.equal(attributeValue({ tag, attributeName: 'href' }), WEB_APP_URL);
  }
});

test('ページの中の # で始まるリンクの宛先の id がページにある', () => {
  const fragmentHrefs = linkHrefs.filter((href) => href.startsWith('#'));
  assert.ok(fragmentHrefs.length >= 1);
  for (const href of fragmentHrefs) {
    assert.ok(landingPageHTML.includes(` id="${href.slice(1)}"`), href);
  }
});

test('画像はすべて docs/ にあるファイルを指し、代替テキストと大きさを持つ', () => {
  const imageTags = openingTags({ tagName: 'img' });
  assert.ok(imageTags.length >= 1);
  for (const tag of imageTags) {
    const source = attributeValue({ tag, attributeName: 'src' });
    assert.ok(existsSync(new URL(source, docsDirectoryURL)), source);
    assert.ok(attributeValue({ tag, attributeName: 'alt' }).length > 0, source);
    assert.match(attributeValue({ tag, attributeName: 'width' }), /^\d+$/, source);
    assert.match(attributeValue({ tag, attributeName: 'height' }), /^\d+$/, source);
  }
});

test('古い公開 URL (bannzai.github.io) がページに無い', () => {
  assert.ok(!landingPageHTML.includes('bannzai.github.io'));
});

test('https で始まるリンクは Web 版だけ', () => {
  // 規約などのページは同じドメインの相対パスで開く。App Store は審査待ち、Google Play は未申請でストアのページが無いため、
  // ストアへのリンクも置かない (issue #362)。ストアのページができたら、その URL をこの期待値に足す
  assert.deepEqual([...new Set(linkHrefs.filter((href) => href.startsWith('http')))], [WEB_APP_URL]);
});
