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
- オンデバイスの画像分類 (ML Kit) の Flutter プラグインは Web 非対応 (同上)

## Decision

| レイヤ | 決定 | 理由 |
| --- | --- | --- |
| クライアント | Flutter + Flame | 立ち上げ設定で確定。bannzai/kashakeibo (Flutter × Firebase のストア配信) と bannzai/egg_clicker (Flame) の資産を流用する |
| 写真の理解と文章の生成 | Claude API (vision)。Cloud Functions (gen2) 経由で呼び、API キーは Secret Manager に置く。未成年向けの安全策として、システムプロンプトに子ども向けの制約 (暴力・性的・差別的な表現を出さない、写真の人物の特徴を書かない) を入れ、名前・図鑑の文章が AI 生成であることをアプリに表示し、生成の前後でコンテンツフィルタ (下の「不適切な画像」と、生成した文章の禁止語の検査) を通す | Gemini API の 18 歳以上の制約を避ける。Anthropic は未成年が触れる製品に安全策 (年齢確認・コンテンツフィルタ等の技術的な対策、子どもの安全向けのシステムプロンプト、法令順守、AI と対話していることの開示) を条件に認めている ( https://support.claude.com/en/articles/9307344-responsible-use-of-anthropic-s-models-guidelines-for-organizations-serving-minors )。年齢確認は「use case に合った技術的な対策」の例示のひとつで、ゲームに年齢入力を置く代わりにフィルタとプロンプトで満たす。クライアント直呼びにすると生成回数の上限を強制できず LLM 原価の上限を守れない (kashakeibo ADR 0001 と同じ判断)。Claude には被写体の構造化した説明 (何か・色・素材・大きさ・硬さ等)・名前・図鑑の文章・見た目のパラメータ (主色・副色・形・目の位置) を JSON で出させる |
| 属性・技・ステータスの判定 | Jev (TypeSafe の判定 API)。Claude の構造化した説明を state にし、master の属性ごとの当てはまり (Noul)、技の候補の選択 (Choice)、ステータスの段階 (Score) を 1 リクエストで判定する。同じく Cloud Functions 経由 | bannzai の返答 (早い・安い)。Jev の入力は文字列だけのため ( https://docs.typesafe.ai/models.md 「Jev reads natural-language text」)、画像は先に Claude で文字列にする。1 リクエストに複数の問いを入れられ、問いの型は Noul・Choice・Score の 3 つ ( https://docs.typesafe.ai/api.md 。`state` は「The content all questions in this request refer to」)。Claude の返答は同じ写真でも揺れるため、最初に得た構造化した説明を生成レコードに保存し、ステータスはその保存した説明と Jev の段階から決定的に計算する (個体値の擬似乱数の seed は保存した説明のハッシュ)。計算の手順には版番号を付けてモンスターに保存し、後で式を変えても既存のモンスターの値は変えない (既存アプリの「生成物が変わる」不満への答え) |
| master に無い属性・技 | Jev の当てはまりがすべて閾値未満の時だけ、Claude に master のスキーマ (名前・説明・属性・威力・PP・相性の行と列) で新しい定義を 1 件提案させ、サーバーが値域 (威力・PP の上下限、相性は 0.5 / 1 / 2) を検証して `definitions/` に版付きで保存する。新しい属性の相性は既存の全属性と等倍を既定にし、agent が後で相性表を更新する。上限は属性 24 種・技 2,000 件で、超えたら最も近い既存の定義を使う | bannzai の返答 (「登録したときに既存のカテゴリにならず属性や技が相応しいと判断した場合はそのときに作る」)。Claude は判定 (選ぶ) を代替せず、候補が無い時の提案だけを担う。相性表の既定値と上限が無いと PvP の公平性と master の増え方を制御できない |
| モンスターの見た目 | 最初の版は Claude が返す見た目のパラメータから Flame で描く (費用ゼロ・決定的)。AI の画像生成は見た目の方向の判断 (#7) で採用が決まった時に、原価・規約 (未成年)・決定性 (生成画像を保存して再生成しない) を本 ADR の後続に書く | 「被写体に似ている」を満たす最小の形で、生成 1 体の原価を増やさない |
| 認証 | Firebase Authentication の匿名ログイン → Sign in with Apple / Google へのアカウントリンク。Firebase App Check を必須にする (iOS: App Attest / DeviceCheck、Android: Play Integrity、Web: reCAPTCHA Enterprise) | 登録なしで使い始められ、二重登録の判定と PvP に要る uid が最初から取れる。引き継ぎはリンクで行う。匿名ログインは uid を作り放題のため、App Check で正規のアプリ以外からの呼び出しを弾く |
| DB | Firestore | ユーザーごとの図鑑・手持ち・PvP で見せる相手のデータを置く。Flutter との組み合わせは kashakeibo で実証済み。レベル・ステータス・バトルの結果はクライアントから書けず (Security Rules で `users/{uid}/monsters/*` の `level` 等を deny)、Functions がバトルの結果を検証して書く (1 戦あたり +1、1 日の戦闘回数の上限) |
| 画像ストレージ | Cloud Storage for Firebase (Blaze) | 元の写真を図鑑に残す。uid 配下 (`users/{uid}/...`) に Security Rules で閉じ、他人には見せない (他人に見せるのはモンスターの見た目のパラメータ・名前・ステータスだけ。共有カードにも元の写真を入れない) |
| サーバーコード | Cloud Functions (gen2)。生成 (SafeSearch → Claude → Jev → 保存)、二重登録の判定、PvP の相手の取得、バトル結果の検証と保存、アカウント削除。再試行は Cloud Tasks のキュー | API キーをクライアントに置かない。Flutter Web でも同じ経路で動く。生成は冪等にする: Functions が受け取った画像から計算するハッシュを冪等キーにし、`users/{uid}/generations/{imageHash}` を Firestore のトランザクションで予約 (期限 10 分の lease 付き。期限切れの予約は再試行が引き継ぐ) してから、状態を safesearch → claude → jev → saved と進める。タイムアウト後の再試行は同じレコードを読んで済んだ段階を飛ばし、有料の API 呼び出しを繰り返さない。「同じ被写体」の二重登録は、Claude の説明から作る正規化キー (種類・主色・素材) が同じユーザーに既にあるかで判定し、あれば生成せず既存のモンスターを返す (撮り直しで画像のハッシュが変わっても被写体の単位で防ぐ) |
| 不適切な画像・人物 | Claude の生成の前に Cloud Vision の SafeSearch (露骨・暴力) と Face Detection を同じリクエストで実行し、露骨な画像と顔が写る画像は生成しない。Label Detection も同じリクエストに入れる (SafeSearch を無料にする条件)。PvP の通報・ブロックは Firestore に記録し、通報されたモンスターは相手の候補から外す | ストアの UGC 要件と、本人を判別できる写真が個人情報に当たること ([PROJECT.md](../PROJECT.md))。Cloud Vision の料金は月 1,000 ユニットまで無料、超過分は 1,000 ユニットあたり $1.50 で、SafeSearch は Label Detection と同じリクエストなら無料 ( https://cloud.google.com/vision/pricing 「Free with Label Detection」)。Face Detection は有料のまま |
| 原価の上限 | uid ごとに 1 日の生成回数の上限 (値は実装時に決めて利用規約と揃える)、プロジェクト全体で 1 日の生成数の上限 (Functions が Firestore のカウンタで判定)、GCP の予算アラート (`/gcp-alert-setup` skill) | 匿名ログインでは uid の上限だけでは原価を抑えられないため、App Check と全体の上限と予算アラートの 3 つで守る |
| Analytics | Firebase Analytics (BigQuery エクスポート) | 判定基準の計測元。Analytics 自体は無料だが、BigQuery エクスポートは BigQuery の料金 (無料枠あり。保存と問い合わせに課金) の対象 ( https://firebase.google.com/docs/projects/bigquery-export 「Your use of BigQuery is subject to BigQuery pricing, which includes limited no-cost use」)。エクスポート先のテーブルの保持期間を 90 日にし、集計は日次の集計テーブルに対して行って問い合わせの量を抑える |
| クラッシュ | Firebase Crashlytics | product-loop がクラッシュ数を読む。通知は #snapmon-notification へ |
| Web 版のホスティング | Firebase Hosting (同じ Firebase プロジェクト) | 本番の配布は、触れる版を見て公開に進むと決まるまで `workflow_dispatch` だけにする |
| 紹介ページ・法務ドキュメント | GitHub Pages (`docs/`) | リポジトリが public で追加のホスティングが要らない |
| 課金・広告 | 最初の版には入れない | 目的が「バズらせる」ため。後から RevenueCat で足せる |
| 環境 | prod のみ (`snapmon-prod`) | 1 人開発で dev 環境の運用コストが見合わない。開発中の検証は Firebase Local Emulator Suite と CI で行う |

## Consequences

- Firebase は Blaze プラン (従量課金) で始める。生成 1 体の原価は未試算。単価の出典: Claude の vision 入力はトークン換算 ( https://platform.claude.com/docs/en/build-with-claude/vision 、料金 https://platform.claude.com/docs/en/about-claude/pricing )、Jev は入力トークンだけに課金で jev-1.13.0 が $42 / 10 億トークン ( https://docs.typesafe.ai/models.md )、Cloud Vision は上の表。実装時に見本 20 件で実測して本 ADR の後続に書く
- サーバーコードが Cloud Functions に集まるため、デプロイ対象はアプリ (3 プラットフォーム) + Functions + Hosting + Pages になる
- Jev と Claude の 2 段構成のため、生成の待ち時間は 2 回の API 呼び出し分になる (既存アプリで褒められている「生成の速さ」を落とさないよう、計測して見直す)
- TypeSafe は前払いのクレジット制で、切れると API が 402 を返して生成が止まる (jev skill `~/.claude/skills/jev/SKILL.md` エラーハンドリングの「クレジット切れの 402」)。Jev が答えない時は Claude に判定を代わらせず (属性・技・ステータスの決め方を master + Jev に固定するため)、生成レコードを `pending_judge` で保存してクライアントには待ち状態を返し、Cloud Tasks の再試行が同じレコードを続きから処理する。Claude の段階は済んでいるため、復帰後に再課金は起きない
- 登録時にその場で作った属性・技の定義は Firestore に版付きで保存し、モンスターには定義の ID と master の版を保存する ([DIRECTION.md](../DIRECTION.md)「決めたこと」)。master の更新で既存のモンスターの値・技を変えない
