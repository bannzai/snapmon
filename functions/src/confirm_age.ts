import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { hasReachedMinimumAge } from "./age";

/**
 * 年齢の確認の結果をサーバーで検査し、Auth のカスタムクレーム `ageVerified: true` を付ける callable。
 *
 * 受け取る data: `{ birthYear: number, birthMonth: number }`。生年月は判定にだけ使い、保存しない (集める個人情報を減らすため)。
 * 返す値: `{ ageVerified: true }`。クライアントは `getIdToken(true)` でクレームの付いたトークンに更新してから、
 * Rules がクレームを必須にしている Firestore・Storage と、Analytics の初期化に進む。
 * 最低年齢に達していなければ `users/{uid}` に `ageRejected: true` を書いて `failed-precondition` を投げ、クレームを付けない。
 * 判定は uid ごとに 1 回だけ有効にする: `ageRejected` のある uid は別の生年月で呼び直しても通さず、`ageAccepted` のある uid は通す
 * (13 歳未満と判定された子どもが年齢を入れ直して通るのを防ぐため。PR #21 のレビュー指摘)。
 * 判定の読み書きはトランザクションで行い、同じ uid から同時に呼んでも判定が 2 通りに分かれない。
 * 限界: 匿名ログインをやり直すと別の uid になり、この印は引き継がれない (アプリのデータを消すと入れ直せる)。
 * 端末に拒否を残して年齢の入力を出し直さない処理は、年齢の確認の画面 (#11) で行う。
 * 既にクレームがある uid に再度呼んでも同じ結果になる (冪等)。
 */
export const confirmAge = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "匿名ログインの後に呼んでください");
  }
  const { birthYear, birthMonth } = (request.data ?? {}) as { birthYear?: unknown; birthMonth?: unknown };
  if (typeof birthYear !== "number" || typeof birthMonth !== "number") {
    throw new HttpsError("invalid-argument", "birthYear と birthMonth を数値で渡してください");
  }
  const auth = getAuth();
  const user = await auth.getUser(request.auth.uid);
  if (user.customClaims?.ageVerified === true) {
    return { ageVerified: true };
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${request.auth.uid}`);
  const accepted = await firestore.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userDocument);
    if (userSnapshot.get("ageRejected") === true) {
      return false;
    }
    if (userSnapshot.get("ageAccepted") === true) {
      return true;
    }
    const reachedMinimumAge = hasReachedMinimumAge({ birthYear, birthMonth, now: new Date() });
    transaction.set(userDocument, reachedMinimumAge ? { ageAccepted: true } : { ageRejected: true }, { merge: true });
    return reachedMinimumAge;
  });
  if (!accepted) {
    throw new HttpsError("failed-precondition", "13 歳未満の方は利用できません");
  }
  await auth.setCustomUserClaims(request.auth.uid, { ...user.customClaims, ageVerified: true });
  return { ageVerified: true };
});
