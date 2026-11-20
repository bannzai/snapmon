// Web 版を Firebase Emulator につないだ動作確認 (`.github/workflows/browser-session.yml` の `firebase_emulator=true`) で、
// ブラウザから Functions の Emulator への呼び出しに、署名の無い偽の App Check のトークンを足す。
//
// 要る理由: Functions は App Check のトークンの無い呼び出しを断る (functions/src/app_check.ts の ENFORCE_APP_CHECK)。
//   一方、Emulator につなぐ Web のビルドは App Check を始めない (App Check に Emulator は無く、始めると本番へ証明を取りに行くため。
//   lib/firebase/session.dart の activateAppCheck)。足さないと「対戦をする」などの Functions の呼び出しがすべて
//   `[firebase_functions/unauthenticated] Unauthenticated [401]` になる (2026-11-20 の run 44698046421 で実測)。
//
// 偽のトークンは Emulator でしか通らない: Functions の Emulator はトークンを検証せずに中身だけを読む
//   (functions/test/emulator/pvp.test.ts の fakeAppCheckToken と同じ形)。本番の Functions は署名を検証するため、
//   このトークンを付けた呼び出しは本番では断られる。本番の App Check の強制は変えない。
//
// Usage: ブラウザを操作する agent-browser の、セッションの最初の `open` に `--init-script` で付ける
//   agent-browser --cdp <webtunnel-cli.sh cdp が出す URL> --init-script scripts/add-functions-emulator-app-check-token.js open http://localhost:8090/
//   セッションの最初の操作より後に付けても効かない (登録の後に読み込み直しても効かず、新しいセッション名の最初の `open` に
//   付けると効いた。2026-11-20 に実測)。同じセッションで後から開くタブ (`tab new`) にも効く。
// 冪等: 同じページに 2 回読み込まれても、fetch を包むのは 1 回だけ。
(() => {
  if (window.fetchAddsFunctionsEmulatorAppCheckToken) {
    return;
  }

  // firebase.json の emulators.functions.port と同じ
  const functionsEmulatorPort = '5001';

  /** value を JSON にして、JWT の区切りに使う base64url (パディング無し) にした文字列を返す。 */
  const encodeJWTPart = ({ value }) => btoa(JSON.stringify(value)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  // aud のプロジェクトは Emulator のプロジェクト (lib/firebase/emulator.dart の _firebaseEmulatorProjectID) と同じ。
  // sub は Functions の Emulator のテストの fakeAppCheckToken と同じ、実在しないアプリの ID
  const fakeAppCheckToken = [
    encodeJWTPart({ value: { alg: 'none', typ: 'JWT' } }),
    encodeJWTPart({ value: { sub: '1:000000000000:web:emulator', aud: ['projects/demo-snapmon'] } }),
    '',
  ].join('.');

  const originalFetch = window.fetch;
  window.fetch = (input, init) => {
    const isRequest = typeof input !== 'string' && !(input instanceof URL);
    if (new URL(isRequest ? input.url : String(input), window.location.href).port !== functionsEmulatorPort) {
      return originalFetch(input, init);
    }
    const headers = new Headers((init && init.headers) || (isRequest ? input.headers : undefined));
    headers.set('X-Firebase-AppCheck', fakeAppCheckToken);
    return originalFetch(input, { ...init, headers });
  };
  window.fetchAddsFunctionsEmulatorAppCheckToken = true;
})();
