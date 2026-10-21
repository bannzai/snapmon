# 0001. 技術スタック: Flutter + Flame × Firebase × Claude API × Jev

## Status

Accepted

## Context

snapmon は、撮った写真の被写体がモンスターになってターン制で戦うゲーム。配信先は iOS / Android / Web (立ち上げ設定)、目的は「バズらせる」ことで、その後すぐにストアへ申請できる状態にする (作るかの判断: https://github.com/bannzai/snapmon/issues/2#issuecomment-6308773377 )。仕様で決まっているのは [DIRECTION.md](../DIRECTION.md)「ゲームの仕様」のとおりで、ここでは次の制約が効く。

- 同じユーザーの同じ被写体を二重に登録しない判定と PvP に、ユーザーの識別とサーバー側のデータが要る
- 名前・図鑑の文章は LLM、属性・技・ステータスは master ファイルと Jev で決める (bannzai の返答)。どちらも API キーをクライアントに置けない
- Gemini API は利用者を 18 歳以上に限る規約があり、ポケモン風の見た目は子どもが使う可能性が高い ([PROJECT.md](../PROJECT.md)「設計の制約」)
- Cloud Storage for Firebase と Cloud Functions は Blaze プラン (従量課金) が要る (同上)
- 他人のモンスター (他人の写真から作った物) を見せる PvP は、App Store / Google Play の UGC 要件 (フィルタ・通報・ブロック・連絡先) の対象になる (同上)

## Decision

| レイヤ | 決定 | 理由 |
| --- | --- | --- |
| クライアント | Flutter + Flame | 立ち上げ設定で確定。bannzai/kashakeibo (Flutter × Firebase のストア配信) と bannzai/egg_clicker (Flame) の資産を流用する |
| 写真の理解と文章の生成 | Claude API (vision)。Cloud Functions (gen2) 経由で呼び、API キーは Secret Manager に置く | Gemini API の 18 歳以上の制約を避ける。Anthropic は未成年が触れる製品に安全策 (年齢確認・コンテンツフィルタ・AI であることの開示) を条件に認めている ( https://support.claude.com/en/articles/9307344-responsible-use-of-anthropic-s-models-guidelines-for-organizations-serving-minors )。クライアント直呼びにすると uid ごとの生成回数の上限を強制できず LLM 原価の上限を守れない (kashakeibo ADR 0001 と同じ判断)。Claude には被写体の構造化した説明 (何か・色・素材・大きさ・硬さ等)・名前・図鑑の文章を出させる |
| 属性・技・ステータスの判定 | Jev (TypeSafe の判定 API)。Claude の構造化した説明を state にし、master ファイルの属性・技の候補への当てはまり (Choice) とステータスの段階 (Score) を 1 リクエストで判定する。同じく Cloud Functions 経由 | bannzai の返答 (早い・安い)。Jev の入力は文字列だけのため ( https://docs.typesafe.ai/models.md )、画像は先に Claude で文字列にする。最終のステータス値は Jev の段階と、説明文のハッシュから引いた擬似乱数の個体値で決定的に計算し、同じ入力からは同じ値にする (既存アプリの「生成物が変わる」不満への答え) |
| 認証 | Firebase Authentication の匿名ログイン → Sign in with Apple / Google へのアカウントリンク | 登録なしで使い始められ、二重登録の判定と PvP に要る uid が最初から取れる。引き継ぎはリンクで行う |
| DB | Firestore | ユーザーごとの図鑑・手持ち・PvP で見せる相手のデータを置く。Flutter との組み合わせは kashakeibo で実証済み |
| 画像ストレージ | Cloud Storage for Firebase (Blaze) | 元の写真を図鑑に残す。uid 配下 (`users/{uid}/...`) に Security Rules で閉じ、他人には見せない (他人に見せるのはモンスターの画像とステータスだけ) |
| サーバーコード | Cloud Functions (gen2)。生成 (Claude → Jev → 保存)、二重登録の判定、不適切な画像の判定、PvP の相手の取得 | API キーをクライアントに置かない。Flutter Web でも同じ経路で動く (オンデバイスの画像分類は Web 非対応) |
| 不適切な画像 | Claude の生成の前に Cloud Vision SafeSearch で判定し、露骨な画像は生成しない。PvP の通報・ブロックは Firestore に記録し、通報されたモンスターは相手の候補から外す | ストアの UGC 要件。SafeSearch は Label Detection と併用で無料 ( https://cloud.google.com/vision/pricing ) |
| Analytics | Firebase Analytics (BigQuery エクスポート) | 判定基準の計測元。追加コストゼロで乗る標準構成 |
| クラッシュ | Firebase Crashlytics | product-loop がクラッシュ数を読む。通知は #snapmon-notification へ |
| Web 版のホスティング | Firebase Hosting (同じ Firebase プロジェクト) | 本番の配布は、触れる版を見て公開に進むと決まるまで `workflow_dispatch` だけにする |
| 紹介ページ・法務ドキュメント | GitHub Pages (`docs/`) | リポジトリが public で追加のホスティングが要らない |
| 課金・広告 | 最初の版には入れない | 目的が「バズらせる」ため。後から RevenueCat で足せる |
| 環境 | prod のみ (`snapmon-prod`) | 1 人開発で dev 環境の運用コストが見合わない。開発中の検証は Firebase Local Emulator Suite と CI で行う |

## Consequences

- Firebase は Blaze プラン (従量課金) で始める。Claude・Jev・Cloud Vision の原価は生成 1 体あたり数円未満の見込みだが、uid ごとの 1 日の生成回数に上限を置いて上限を守る
- サーバーコードが Cloud Functions に集まるため、デプロイ対象はアプリ (3 プラットフォーム) + Functions + Hosting + Pages になる
- Jev と Claude の 2 段構成のため、生成の待ち時間は 2 回の API 呼び出し分になる (既存アプリで褒められている「生成の速さ」を落とさないよう、計測して見直す)
- TypeSafe のクレジットが切れると生成が止まる。Jev が答えない時は Claude に属性・技の選択まで任せる予備の経路を Functions に持つ
