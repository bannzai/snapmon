// docs/index.html (紹介ページ) が、外から決まった URL で開かれ続けることと、リンク・画像の宛先が切れていないことのテスト。
// 実行: node --test scripts/test/test-landing-page.mjs (リポジトリのルートで)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const docsDirectoryURL = new URL('../../docs/', import.meta.url);
const landingPageHTML = readFileSync(new URL('index.html', docsDirectoryURL), 'utf8');

// 紹介ページを公開している URL。GitHub Pages の独自ドメイン (docs/CNAME) と同じ
const LANDING_PAGE_URL = 'https://snapmonster.app/';
// 「今すぐ遊ぶ」の宛先 (Web 版)。Firebase Hosting の snapmon-prod に向けた独自ドメインで、2026-11-18T06:12Z に curl で 200 を確かめた
// (issue #362 の「200 を返すなら play.snapmonster.app」)
const WEB_APP_URL = 'https://play.snapmonster.app/';

/** landingPageHTML の中の、tagName の開始タグの文字列をすべて返す。 */
function openingTags({ tagName }) {
  return landingPageHTML.match(new RegExp(`<${tagName}\\b[^>]*>`, 'g')) ?? [];
}

/** 開始タグの文字列 tag の、attributeName の属性の値を返す。属性が無ければ undefined。 */
function attributeValue({ tag, attributeName }) {
  return tag.match(new RegExp(`\\s${attributeName}="([^"]*)"`))?.[1];
}

/**
 * 非可逆の WebP (RIFF の最初のチャンクが `VP8 `) の bytes から、画素の幅と高さを返す。
 * 幅と高さは、フレームの開始符号 (9d 01 2a) の直後に 14 ビットずつリトルエンディアンで入っている (RFC 6386 の 9.1)。
 * 別の形 (可逆の `VP8L`・拡張の `VP8X`) の時は、切り出しのスクリプトが書き出す形が変わったと分かるように throw する。
 */
function lossyWebPSize({ bytes }) {
  assert.equal(bytes.toString('latin1', 0, 4), 'RIFF');
  assert.equal(bytes.toString('latin1', 8, 16), 'WEBPVP8 ');
  assert.deepEqual([...bytes.subarray(23, 26)], [0x9d, 0x01, 0x2a]);
  return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
}

/** fastlane/metadata の直下の、App Store の掲載文を持つ言語のディレクトリの名前 (android などの言語でないディレクトリを除く)。 */
const appStoreLocales = readdirSync(new URL('../../fastlane/metadata/', import.meta.url)).filter((name) =>
  existsSync(new URL(`../../fastlane/metadata/${name}/support_url.txt`, import.meta.url)),
);

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

test('切り出しのスクリプトが書き出す画像・docs/images/ のファイル・ページが使う画像が一致する', () => {
  // スクリーンショットを作り直した時に scripts/landing_page/crop_landing_page_images.py を実行すれば、ページの画像がすべて新しくなることを保つ
  const scriptOutputNames = [
    ...readFileSync(new URL('../landing_page/crop_landing_page_images.py', import.meta.url), 'utf8').matchAll(/^ {4}"([^"]+\.webp)": \(/gm),
  ].map((match) => match[1]);
  assert.ok(scriptOutputNames.length >= 1);
  assert.deepEqual(readdirSync(new URL('images/', docsDirectoryURL)).sort(), [...scriptOutputNames].sort());
  assert.deepEqual(
    openingTags({ tagName: 'img' }).map((tag) => attributeValue({ tag, attributeName: 'src' })).sort(),
    scriptOutputNames.map((name) => `./images/${name}`).sort(),
  );
});

test('画像の width・height の属性が、画像のファイルの画素の幅 (600) と高さに一致する', () => {
  // 属性が実際の大きさと違うと、読み込みの前後で縦横比が変わって表示がずれる。幅 600 は、ページで出す最大の幅 300 CSS px の 2 倍
  for (const tag of openingTags({ tagName: 'img' })) {
    const source = attributeValue({ tag, attributeName: 'src' });
    const size = lossyWebPSize({ bytes: readFileSync(new URL(source, docsDirectoryURL)) });
    assert.equal(size.width, 600, source);
    assert.equal(Number(attributeValue({ tag, attributeName: 'width' })), size.width, source);
    assert.equal(Number(attributeValue({ tag, attributeName: 'height' })), size.height, source);
  }
});

test('App Store の掲載文のサポート URL とプライバシーポリシーの URL が、紹介ページのドメインの決まったパスを指す', () => {
  assert.ok(appStoreLocales.includes('ja'));
  assert.ok(appStoreLocales.includes('en-US'));
  for (const locale of appStoreLocales) {
    const localeDirectoryURL = new URL(`../../fastlane/metadata/${locale}/`, import.meta.url);
    assert.equal(readFileSync(new URL('support_url.txt', localeDirectoryURL), 'utf8').trim(), `${LANDING_PAGE_URL}#support`, locale);
    assert.equal(readFileSync(new URL('privacy_url.txt', localeDirectoryURL), 'utf8').trim(), `${LANDING_PAGE_URL}PrivacyPolicy`, locale);
  }
});

test('App Store と Google Play の説明文の中の URL は、紹介ページのドメインのものだけ', () => {
  for (const descriptionURL of [
    ...appStoreLocales.map((locale) => new URL(`../../fastlane/metadata/${locale}/description.txt`, import.meta.url)),
    ...readdirSync(new URL('../../fastlane/metadata/android/', import.meta.url)).map(
      (locale) => new URL(`../../fastlane/metadata/android/${locale}/full_description.txt`, import.meta.url),
    ),
  ]) {
    const urlsInDescription = readFileSync(descriptionURL, 'utf8').match(/https?:\/\/[^\s)]+/g) ?? [];
    assert.ok(urlsInDescription.length >= 1, descriptionURL.pathname);
    for (const url of urlsInDescription) {
      assert.ok(url.startsWith(LANDING_PAGE_URL), `${descriptionURL.pathname}: ${url}`);
    }
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
