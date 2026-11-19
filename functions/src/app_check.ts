/**
 * onCall の App Check の強制 (`enforceAppCheck`) を一箇所で切り替える値。
 *
 * true: App Check のトークンが無い・検証を通らない呼び出しを 401 で断る。ADR 0001 の認証の行が App Check を必須にする根拠。
 * 公開前の確認期間 (2026-10-25 から) は false にしていて、ストア申請の前に true に戻した
 * (bannzai の判断。DIRECTION.md「決めたこと」2026-11-19 の App Check の行)。
 * false にしても firebase-functions はトークンの検証結果をログ (`callable-request-verification`) に残す。
 */
export const ENFORCE_APP_CHECK = true;
