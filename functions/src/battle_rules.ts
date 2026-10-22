/**
 * レベルの上限。クライアントの lib/domain/monster/monster_state.dart の maximumLevel と同じ値
 * (documents/DIRECTION.md「ゲームの仕様」の「上限は 999」)。
 */
export const MAXIMUM_LEVEL = 999;

/**
 * 1 日に記録できるバトルの数の上限。原価と不正 (レベル上げの連打) の抑えとして agent が決めた値 (documents/adr/0001-tech-stack.md の DB の行)。
 */
export const DAILY_BATTLE_LIMIT = 50;

/** 手持ちの数の上限 (documents/DIRECTION.md「ゲームの仕様」の「手持ちは 3 体まで」)。 */
export const MAXIMUM_PARTY_SIZE = 3;

/** 1 日の区切りに使う時差 (分)。利用者の多くが日本にいる想定のため、日本時間 (UTC+9) の 0 時で区切る。 */
const BATTLE_DAY_UTC_OFFSET_MINUTES = 9 * 60;

/**
 * [now] が属する「1 日」(日本時間) を `YYYY-MM-DD` で返す。1 日のバトルの数を数える単位に使う。
 */
export function battleDayKey({ now }: { now: Date }): string {
  return new Date(now.getTime() + BATTLE_DAY_UTC_OFFSET_MINUTES * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * [value] がモンスターの ID の列 (空でない文字列を重複なく 1 件以上 [MAXIMUM_PARTY_SIZE] 件以下) かを判定する。
 */
export function isMonsterIdList(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.length >= 1 &&
    value.length <= MAXIMUM_PARTY_SIZE &&
    value.every((monsterId) => typeof monsterId === "string" && monsterId !== "" && !monsterId.includes("/")) &&
    new Set(value).size === value.length
  );
}

/**
 * 戦闘に出たモンスター [participantMonsterIds] が、バトルの開始時に記録した手持ち [partyMonsterIds] に含まれるかを判定する。
 * 手持ちに無いモンスターのレベルを上げさせないため。
 */
export function isSubsetOfParty({
  participantMonsterIds,
  partyMonsterIds,
}: {
  participantMonsterIds: string[];
  partyMonsterIds: string[];
}): boolean {
  return participantMonsterIds.every((monsterId) => partyMonsterIds.includes(monsterId));
}

/** 1 戦の後のレベルを返す。勝敗に関係なく 1 上がり、[MAXIMUM_LEVEL] で止まる。 */
export function levelAfterBattle({ level }: { level: number }): number {
  return Math.min(level + 1, MAXIMUM_LEVEL);
}
