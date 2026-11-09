---
paths:
  - "firebase/**"
  - "functions/**"
  - "lib/**/*.dart"
---

# Firestore・Storage の規約

構造と書き込みの主体の根拠は `documents/adr/0001-tech-stack.md` (DB・画像ストレージ・サーバーコードの行)。

## 構造

| パス | 中身 | クライアント | Functions (Admin SDK) |
| --- | --- | --- | --- |
| `master/{version}` | master (属性・技・相性表・分類) の 1 つの版。数値の `version` を持つ | 読む (ログインしたユーザー) | `functions/scripts/seed-master.mjs` が投入。投入済みの版は書き換えない |
| `definitions/{definitionId}` | 生成時にその場で作った属性・技の定義 | 読む (ログインしたユーザー) | 書く |
| `users/{uid}` | 生成中ロック (`generationLock`)、uid ごとの 1 日の生成数 (`dailyGeneration`)、`dailyBattleDate`・`dailyBattleCount` (recordBattle が 1 日 50 戦の上限の判定に使う、日本時間の日付とその日に記録したバトルの数)、`displayName` (setDisplayName が禁止語の検査を通して書く表示名。無ければ Functions が uid から既定の名前を決める)、`iconPath` (setProfileIcon が Cloud Vision の検査を通したアイコンの Storage のパス `users/{uid}/icons/{uploadId}.png`。無ければクライアントが既定の印を描く)、`dailyIconCheck` (setProfileIcon が uid ごとの 1 日の検査の上限の判定に使う、日本時間の日付とその日の検査の数)、`accountDeletionStartedAt` (deleteAccount が削除を始めた時刻。付いている間は生成とバトルの開始を受け付けない。`users/{uid}` と一緒に最後に消える)、`generationTickets` (生成チケットの残高。RevenueCat の webhook `revenueCatWebhook` が購入で足し、生成の予約が 1 日の無料の回数を使い切った後に 1 枚ずつ減らす。無ければ 0 枚。`functions/src/generation_tickets.ts`)、`actionCardCredits` (Action Card の残高。`rank1`・`rank2`・`rank3` ごとの枚数。同じ webhook が購入で足し、redeemActionCard が技を買い切る時に 1 枚ずつ減らす。無いランクは 0 枚。`functions/src/action_cards.ts`) 等。最初の生成の予約がこのドキュメントを作るため、図鑑のモンスターがいるユーザーには必ずある。Functions は、`users/{uid}` が無く Auth のユーザーも無い uid をアカウントの削除を消し終えたものとして断る (削除は Auth のユーザーを先に消すため。`functions/src/account.ts` の `authUserExists`) | 本人が読む | 書く |
| `users/{uid}/monsters/{monsterId}` | 図鑑のモンスター (形は `functions/src/generation/records.ts` の `MonsterDocument`)。`actionCardMoveIds` (Action Card で覚えさせた技の ID。覚えさせた順) は teachActionCardMove・forgetActionCardMove が書き、生まれた時に決まる値ではない | 本人が読む | 書く |
| `users/{uid}/generations/{requestId}` | 生成の状態遷移のレコード (形は `functions/src/generation/records.ts` の `GenerationRecord`) | 本人が読む | 書く |
| `users/{uid}/ticketPurchases/{eventId}` | 生成チケットの購入の記録 (形は `functions/src/generation_tickets.ts` の `TicketPurchaseDocument`。ID は RevenueCat のイベントの ID)。同じイベントの再送で 2 回足さない判定と購入の履歴に使う | 本人が読む | 書く |
| `users/{uid}/actionCardPurchases/{eventId}` | Action Card の購入の記録 (形は `functions/src/generation_tickets.ts` の `ActionCardPurchaseDocument`。ID は RevenueCat のイベントの ID)。使い方は `ticketPurchases` と同じ | 本人が読む | 書く |
| `users/{uid}/actionCards/{moveId}` | 買い切った技 (形は `functions/src/action_cards.ts` の `ActionCardDocument`)。redeemActionCard が作り、持っている間は本人のどのモンスターにも覚えさせられる | 本人が読む | 書く |
| `users/{uid}/generationAliases/{requestId}` | 同じ写真・マスクの組で別の要求 ID の結果を使い回した要求の、使い回し先 (`reusedRequestId`)。同じ要求 ID の再送に結果を返すため | 読み書きしない | 書く |
| `generationDailyCounts/{YYYY-MM-DD}` | プロジェクト全体の 1 日の生成数 (原価の上限のカウンタ。日付は日本時間) | 読み書きしない | 書く |
| `moveUsageDailyCounts/{YYYY-MM-DD}` | 技の 1 日の使用回数 (`counts.{moveId}`。日付は日本時間)。recordBattle が参加したモンスターの技の枠の技を 1 ずつ足し、updateMoveRanks が技のランクを決めるのに使う (ランクは購入の可否の判定に使う値で、集計のサマリーに当たらない) | 読み書きしない | 書く |
| `moveRanks/current` | 技のランクの表 (形は `functions/src/action_cards.ts` の `MoveRanksDocument`)。updateMoveRanks が毎日書く | 読む (ログインしたユーザー) | 書く |
| `config/features` | 機能を出すかの切り替え (`actionCardsVisible`: Action Card の画面を出すか。無ければ出さない) | 読む (ログインしたユーザー) | `functions/scripts/set-feature-flag.mjs` が書く |
| `iconCheckDailyCounts/{YYYY-MM-DD}` | プロジェクト全体の 1 日のアイコンの検査の数 (Cloud Vision の原価の上限のカウンタ。日付は日本時間。`functions/src/profile.ts`) | 読み書きしない | 書く |
| `definitionCounters/global` | その場で作った属性・技の数 (上限のカウンタ) | 読み書きしない | 書く |
| `users/{uid}/battles/{battleId}` | バトルの開始と完了の記録 (startBattle が `status: "started"`・`partyMonsterIds` で作り、recordBattle が `status: "completed"`・`participantMonsterIds`・`winner`・`turnCount`・`levels` を足す) | 本人が読む | 書く |
| `users/{uid}/party/current` | 手持ち (`monsterIds`: 自分の monsters の ID を重複なく 3 件まで、`updatedAt`) | 本人が読み書き | - |
| `users/{uid}/settings/current` | 端末の設定 | 本人が読み書き | - |
| `reports/{reporterUid}_{monsterId}` | PvP の通報 (形は `functions/src/pvp_rules.ts` の `ReportDocument` と `createdAt`。通報した時点の持ち主のアイコンのパス `monsterOwnerIconPath` を含む)。作られると notifyReport が #snapmon-notification に知らせる。deleteAccount が `reporterUid` で本人の分を探して消す (`functions/src/account.ts`) | 読み書きしない | 書く |
| `reportedMonsters/{monsterId}` | 通報されたモンスターの持ち主 (`monsterOwnerUid`) と通報したユーザー数 (`reporterCount`)。fetchOpponents が候補から外す判定に使う。deleteAccount が `monsterOwnerUid` で本人の分を探して消す | 読み書きしない | 書く |
| `blocks/{blockerUid}_{blockedUid}` | PvP のブロック (`blockerUid`・`blockedUid`・`createdAt`)。fetchOpponents は両方向で候補から外す。deleteAccount が `blockerUid` で本人の分を探して消す | 読み書きしない | 書く |

Storage: `users/{uid}/photos/{requestId}` (元の写真。本人だけ読み書き、4 MB 以下の JPEG・PNG)、`users/{uid}/masks/{requestId}` (端末で決めた切り出しの範囲。iOS の OS の切り出しか crop。本人だけ読み書き、1 MB 以下の PNG)、`users/{uid}/generations/{requestId}/cutout.png` (生成の途中の切り出し画像。本人だけ読み、書くのは Functions だけ)、`monsters/{monsterId}/art.png` (写真から切り出した被写体の画像。ログインした全員が読み、書くのは Functions だけ)、`users/{uid}/iconUploads/{uploadId}` (プロフィールのアイコンにする写真。本人だけ読み書き、名前は UUID の形、4 MB 以下の JPEG・PNG。setProfileIcon が検査の後に消す)、`users/{uid}/icons/{uploadId}.png` (検査を通したアイコン。ログインした全員が読み、書くのは Functions だけ。`users/{uid}/` の配下のため、アカウントの削除で自動で消える)。

## ルール

- 構造 (パス・クライアントが書けるフィールド) を変える時は、`firebase/firestore.rules`・`firebase/storage.rules`・`functions/test/emulator/` の Rules のテスト・この文書を同じ PR で直す
- Rules はすべての読み書きにログイン (匿名ログインを含む) を求める。カスタムクレームは使わない (アプリ内の年齢の確認は置かない。ADR 0001 の対象年齢の行)
- クライアントが書けるのは `party/current` と `settings/current` だけにする。書けるのは `users/{uid}` があり `accountDeletionStartedAt` が無い間だけ (削除の後も別の端末の ID トークンは期限まで通るため)。図鑑・生成・バトルの結果・定義はクライアントから書かせず、Functions が検証してから書く (改ざんで値・レベルを変えさせないため)
- 他人のデータ (PvP の相手の手持ち) はクライアントが直接読まず、Functions (fetchOpponents) が見せてよい項目 (`functions/src/pvp_rules.ts` の `publicMonster` が名指しで写す、切り出した画像・装飾・名前・属性・技・ステータス・レベルと、相手の表示名・アイコンのパス) だけを返す。元の写真の参照は他人に返さない
- 件数・合計などの集計のサマリーをドキュメントに持たない。判定基準の集計は Analytics の BigQuery エクスポートで行い、Firestore に二重に持たない (サマリーと実データが食い違う状態を作らないため)。原価の上限のカウンタ (1 日の生成数) のように、書き込みの可否の判定に使う値は集計のサマリーに当たらない
- master の版とモンスターの生まれた時に決まる値は書き換えない。変える時は新しい版を足す
- 本人のデータを置くパスを足す時は、アカウントの削除 (`functions/src/account.ts` の `deleteAccountData`) が消す範囲に入るか確かめ、入らなければ削除に足して `docs/AccountDeletion.md` の「削除されるデータ」と合わせる。`users/{uid}` の配下と Storage の `users/{uid}/` の配下は自動で消える
