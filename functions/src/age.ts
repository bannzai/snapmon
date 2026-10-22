/**
 * 利用できる最低年齢 (歳)。
 * COPPA が保護者の同意を求める 13 歳未満を対象から外すため (documents/DIRECTION.md「決めたこと」の対象年齢の行)。
 */
export const MINIMUM_AGE_YEARS = 13;

/**
 * 生年月が利用できる年齢に達しているかを判定する。
 *
 * 生年月には日が無いため、生まれた月の末日生まれとみなし、最低年齢の誕生月を過ぎた (翌月以降) 時だけ達しているとする。
 * 誕生月の中では誕生日の前か後かを決められず、13 歳未満を通さない側に倒すため。
 *
 * @param birthYear 西暦の生年 (例: 2010)
 * @param birthMonth 生まれた月 (1〜12)
 * @param now 判定の基準日時。月は UTC で数える (日本時間との差は月の境の 9 時間だけで、上の判定の余裕に収まる)
 * @returns 達していれば true。生年月が実在しない値 (月の範囲外・未来) なら false
 */
export function hasReachedMinimumAge({
  birthYear,
  birthMonth,
  now,
}: {
  birthYear: number;
  birthMonth: number;
  now: Date;
}): boolean {
  if (!Number.isInteger(birthYear) || !Number.isInteger(birthMonth) || birthMonth < 1 || birthMonth > 12) {
    return false;
  }
  const elapsedMonths = now.getUTCFullYear() * 12 + (now.getUTCMonth() + 1) - (birthYear * 12 + birthMonth);
  return elapsedMonths > MINIMUM_AGE_YEARS * 12;
}
