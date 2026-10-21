import { getAuth } from "firebase-admin/auth";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { hasReachedMinimumAge } from "./age";

/**
 * 年齢の確認の結果をサーバーで検査し、Auth のカスタムクレーム `ageVerified: true` を付ける callable。
 *
 * 受け取る data: `{ birthYear: number, birthMonth: number }`。生年月は判定にだけ使い、保存しない (集める個人情報を減らすため)。
 * 返す値: `{ ageVerified: true }`。クライアントは `getIdToken(true)` でクレームの付いたトークンに更新してから、
 * Rules がクレームを必須にしている Firestore・Storage と、Analytics の初期化に進む。
 * 最低年齢に達していなければ `failed-precondition` を投げ、クレームを付けない。
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
  if (!hasReachedMinimumAge({ birthYear, birthMonth, now: new Date() })) {
    throw new HttpsError("failed-precondition", "13 歳未満の方は利用できません");
  }
  const auth = getAuth();
  const user = await auth.getUser(request.auth.uid);
  await auth.setCustomUserClaims(request.auth.uid, { ...user.customClaims, ageVerified: true });
  return { ageVerified: true };
});
