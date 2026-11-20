// scripts/add-functions-emulator-app-check-token.js (Functions の Emulator への呼び出しに偽の App Check のトークンを足す、
// ブラウザに読み込ませるスクリプト) が、Functions の Emulator への呼び出しにだけトークンを足すことのテスト。
// 実行: node --test scripts/test/test-add-functions-emulator-app-check-token.mjs (リポジトリのルートで)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const scriptSource = readFileSync(new URL('../add-functions-emulator-app-check-token.js', import.meta.url), 'utf8');

// Functions の Emulator が中身を読める App Check のトークン。functions/test/emulator/pvp.test.ts の fakeAppCheckToken と同じ形で、
// aud は Emulator のプロジェクト (lib/firebase/emulator.dart の demo-snapmon)
const EXPECTED_APP_CHECK_TOKEN = [
  Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url'),
  Buffer.from(JSON.stringify({ sub: '1:000000000000:web:emulator', aud: ['projects/demo-snapmon'] })).toString('base64url'),
  '',
].join('.');

// アプリが Functions の Emulator を呼ぶ URL の形 (ホストは browser-session.yml が渡す FIREBASE_EMULATOR_HOST、ポートは firebase.json)
const FUNCTIONS_EMULATOR_URL = 'http://127.0.0.1:5001/demo-snapmon/asia-northeast1/joinPvpMatch';

/**
 * スクリプトを、Web 版のページ (http://localhost:8090/) に読み込んだ時と同じ形の window で実行する。
 * 返す値は、スクリプトをもう一度読み込む関数 load、包まれた後の fetch を呼ぶ関数 fetch、今の window.fetch を返す関数 currentFetch、
 * 元の fetch が受け取った引数の一覧 calls。
 */
function loadIntoPage() {
  const calls = [];
  const window = {
    fetch: (input, init) => {
      calls.push({ input, init });
      return 'original-response';
    },
    location: { href: 'http://localhost:8090/' },
  };
  const context = vm.createContext({ window, Headers, URL, btoa });
  const load = () => vm.runInContext(scriptSource, context);
  load();
  return { load, fetch: (input, init) => window.fetch(input, init), currentFetch: () => window.fetch, calls };
}

/** 元の fetch が受け取った 1 回分の引数 call の、App Check のヘッダーの値を返す。無ければ null。 */
function appCheckHeader({ call }) {
  return new Headers(call.init?.headers ?? (typeof call.input === 'string' ? undefined : call.input.headers)).get('X-Firebase-AppCheck');
}

test('Functions の Emulator への呼び出しに、Emulator が読める形のトークンを足し、元のヘッダーと応答を保つ', () => {
  const page = loadIntoPage();
  assert.equal(
    page.fetch(FUNCTIONS_EMULATOR_URL, {
      method: 'POST',
      headers: { Authorization: 'Bearer id-token', 'Content-Type': 'application/json' },
      body: '{"data":null}',
    }),
    'original-response',
  );
  assert.equal(page.calls.length, 1);
  const [call] = page.calls;
  assert.equal(call.input, FUNCTIONS_EMULATOR_URL);
  assert.equal(appCheckHeader({ call }), EXPECTED_APP_CHECK_TOKEN);
  assert.equal(call.init.headers.get('Authorization'), 'Bearer id-token');
  assert.equal(call.init.headers.get('Content-Type'), 'application/json');
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.body, '{"data":null}');
});

test('init の無い呼び出し・URL オブジェクト・Request・別のホスト名でも、Functions の Emulator への呼び出しならトークンを足す', () => {
  const page = loadIntoPage();
  page.fetch(FUNCTIONS_EMULATOR_URL);
  page.fetch(new URL(FUNCTIONS_EMULATOR_URL));
  page.fetch(new Request(FUNCTIONS_EMULATOR_URL, { method: 'POST', headers: { Authorization: 'Bearer id-token' }, body: '{}' }));
  page.fetch('http://localhost:5001/demo-snapmon/asia-northeast1/leavePvpMatch');
  assert.equal(page.calls.length, 4);
  for (const call of page.calls) {
    assert.equal(appCheckHeader({ call }), EXPECTED_APP_CHECK_TOKEN);
  }
  // Request の元のヘッダーを落とさない
  assert.equal(page.calls[2].init.headers.get('Authorization'), 'Bearer id-token');
});

test('Functions の Emulator 以外への呼び出しは、引数を変えずに元の fetch へ渡す', () => {
  for (const url of [
    // Firestore・Auth・Storage の Emulator (firebase.json の emulators)
    'http://127.0.0.1:8080/google.firestore.v1.Firestore/Listen/channel',
    'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp',
    'http://127.0.0.1:9199/v0/b/demo-snapmon.appspot.com/o',
    // ポートの数字が 5001 を含むだけの宛先
    'http://127.0.0.1:50010/demo-snapmon/asia-northeast1/joinPvpMatch',
    'http://127.0.0.1:15001/demo-snapmon/asia-northeast1/joinPvpMatch',
    // クエリに :5001/ を含むだけの宛先
    'https://example.com/redirect?to=http://127.0.0.1:5001/demo-snapmon',
    // 本番の Functions (ポートの指定が無い)
    'https://asia-northeast1-snapmon-prod.cloudfunctions.net/joinPvpMatch',
    // Web 版自身の配信 (相対パス。ページのポートは 8090)
    'assets/AssetManifest.bin.json',
  ]) {
    const page = loadIntoPage();
    const init = { headers: { Authorization: 'Bearer id-token' } };
    assert.equal(page.fetch(url, init), 'original-response', url);
    assert.equal(page.calls.length, 1, url);
    assert.equal(page.calls[0].input, url, url);
    assert.equal(page.calls[0].init, init, url);
    assert.equal(appCheckHeader({ call: page.calls[0] }), null, url);
  }
});

test('同じページに 2 回読み込んでも、fetch を包み直さず、元の fetch を 1 回だけ呼ぶ', () => {
  const page = loadIntoPage();
  const fetchAfterFirstLoad = page.currentFetch();
  page.load();
  assert.equal(page.currentFetch(), fetchAfterFirstLoad);
  page.fetch(FUNCTIONS_EMULATOR_URL);
  assert.equal(page.calls.length, 1);
  assert.equal(appCheckHeader({ call: page.calls[0] }), EXPECTED_APP_CHECK_TOKEN);
});
