/**
 * onCall の App Check の強制 (`enforceAppCheck`) を一箇所で切り替える値。
 *
 * false: 公開前の確認期間の設定。Web の reCAPTCHA Enterprise のサイトキーと simulator 用の debug token がまだ無く、
 * 本番に対する通しの確認が App Check のトークン無し (`verifications.app: MISSING`) の 401 で止まるため、トークンを検査せずに通す
 * (bannzai の判断。2026-10-25)。この間も firebase-functions はトークンの有無をログ (`callable-request-verification`) に残すため、
 * 各プラットフォームの App Check が VALID になったのを確かめてから true に戻す。
 * ストア申請 (公開) の前に true に戻す。ADR 0001 の認証の行が App Check を必須にする根拠。
 */
export const ENFORCE_APP_CHECK = false;
