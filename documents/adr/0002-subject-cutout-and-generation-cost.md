# 0002. 被写体の切り出しの範囲は端末で決め、生成の原価を見積もる

## Status

Accepted (2026-10-22)。2026-10-28 に、自動のマスクをサーバーの IS-Net で作る決定を、端末で決める形 (iOS の OS の切り出しと crop) に改めた (下の「改訂 (2026-10-28)」)

## Context

モンスターの絵は、写真から切り出した被写体に装飾を重ねる形にした ([DIRECTION.md](../DIRECTION.md)「決めたこと」2026-10-22。装飾は 2026-10-29 の行でやめ、切り出した画像だけを描く)。[ADR 0001](0001-tech-stack.md)「モンスターの見た目」の行は、自動のマスクを作る場所 (端末内の OS の機能か、サーバー側の AI か)・使う API・原価・Web 版での経路を、生成の実装 (#13) で本 ADR に書くとした。あわせて、同 ADR の Consequences が「実装時に見本 20 件で実測して後続に書く」とした 1 体あたりの原価と、ステータスの計算をどこで行うかもここに書く。

選ぶ時の条件は次のとおり。

- iOS / Android / Web の 3 つで同じように遊べる (立ち上げ設定)
- 13 歳以上の利用者 (未成年を含む) が使う製品で使える規約である (ADR 0001「対象年齢」)
- 同じ写真から同じ切り出しになる、または一度作った結果を保存して変えない (既存アプリの「生成物が変わる」不満)
- 切り出しの適用は常にサーバーが、検査済みの元の写真に対して行う (ADR 0001「モンスターの見た目」)。どの経路でも、クライアントが送るのは元の写真と範囲のマスクだけ

## 比べた選択肢

| 選択肢 | 3 つの配信先 | 規約・新しい外部連携 | 決定性 | 原価 |
| --- | --- | --- | --- | --- |
| 端末内の OS の機能 (iOS の Vision の前景のマスク、Android の ML Kit の Subject Segmentation) | Web に同等の機能が無く、Web は手で範囲を決める経路だけになる。iOS・Android はネイティブの部品を Flutter に繋ぐ実装が要る | 新しい外部連携は無い | 端末と OS の版でマスクが変わる (ただし結果は保存する) | 無料 |
| サーバーで、外部の画像 AI の API (背景除去の SaaS・画像生成 API の編集機能) | 3 つとも同じ経路 | 新しい外部サービスとの連携 (課金・規約の確認) が要り、未成年が使う製品での利用条件を個別に確かめる必要がある | 版の固定はサービスに依存する | 1 枚ごとに課金 |
| **サーバーで、公開されたモデルを Functions の中で動かす (2026-10-22 に採用。改訂 (2026-10-28) で端末内の OS の機能と crop に変更)** | 3 つとも同じ経路 | 外部サービスに写真を送らない。モデルのライセンスだけを確かめればよい | 同じモデルの同じ版・同じ入力からは同じマスク | Functions の実行時間だけ |

## Decision

2026-10-22 の決定。「自動のマスクを作る場所」「モデル」「モデルの配り方」「推論の後処理」「手で範囲を決める経路」の 5 行は、下の「改訂 (2026-10-28)」で置き換えた (経緯のため残す)。

| 項目 | 決定 | 根拠 |
| --- | --- | --- |
| 自動のマスクを作る場所 | サーバー (`generate` の cutout の段階)。Web を含む 3 つの配信先が同じ経路になり、外部サービスに写真を送らない | 上の比較 |
| モデル | IS-Net (DIS) の general-use の重み ( https://github.com/xuebinqin/DIS 。リポジトリのライセンスは Apache-2.0: `gh api repos/xuebinqin/DIS/license` の `spdx_id` が `Apache-2.0`、2026-10-22 に確認) を、rembg が ONNX に書き出した `isnet-general-use.onnx` ( https://github.com/danielgatis/rembg/releases/tag/v0.0.0 。rembg のライセンスは MIT: 同じ確かめ方で `MIT`)。onnxruntime-node で推論し、sharp で画像を扱う | 下の実測で、同じ見本の切り出しが u2netp・silueta より輪郭が細かく (自転車のスポーク・カメラのストラップ)、単色の写真には何も反応しなかった |
| モデルの配り方 | リポジトリに置かず (178 MB)、`functions/scripts/fetch-segmentation-model.mjs` が取得元の URL と SHA-256 (`60920e99…964a`) を固定して `functions/models/` に取得する。デプロイは firebase.json の predeploy、CI は firebase-ci.yml で取得する | 版と中身を固定し、取得元が差し替えられても別のモデルで動かないようにする |
| 推論の後処理 | モデルの出力 (0〜1) を最小・最大で引き伸ばさずにマスクにし、0.5 以上を被写体とみなす。被写体が写真の 1% 未満なら切り出せない写真として rejected (`no_subject`) にし、以後の有料の API を呼ばない | rembg は出力を最小・最大で引き伸ばすため、単色の写真の弱い反応 (最大 0.013) も被写体になってしまう。下の実測で単色の写真は 0%、物の写真は 5.0〜49% だった |
| 手で範囲を決める経路 | クライアントは被写体が白・背景が黒のマスク (PNG・1 MB 以下) を `users/{uid}/masks/{requestId}` に置き、`generate` に `maskPath` を渡す。サーバーはマスクを元の写真の大きさに合わせて適用する。マスクがあれば自動のマスクは作らない | ADR 0001「モンスターの見た目」。補助キー (画像のハッシュとマスクのハッシュの組) が違うため、自動で rejected になった写真を手のマスクで送り直せる |
| 切り出した絵 | 被写体の外接矩形 (長辺の 4% の余白付き) に切り詰めた透明背景の PNG。cutout の段階で `users/{uid}/generations/{requestId}/cutout.png` に置き、saved で `monsters/{monsterId}/art.png` に写して中間のファイルを消す | ADR 0001「画像ストレージ」 |
| ステータスの計算 | Functions が計算して値をモンスターに保存する (Dart の `lib/domain/monster/stat_calculation.dart` の式を `functions/src/generation/monster_stats.ts` に写し、同じ見本で同じ値になることを両方のテストで確かめる) | 値を書くのは Functions だけにする (`.claude/rules/firestore.md`「クライアントが書けるのは party と settings だけ」)。クライアントに段階だけを返して計算させると、改ざんされた値を保存する経路ができる |
| Claude のモデル | `claude-opus-5-5`・effort `low`・structured outputs (`output_config.format`)。安全上の拒否は server-side fallback (`fallbacks: "default"`) に任せ、それでも拒否なら rejected (`refused`) | claude-api skill の既定のモデル。下の原価の見積もりで 1 体の原価の大半を占めるため、本番の実測 (生成レコードの `claudeUsages`) で見直す |
| Jev のモデル | `jev-1.13.0` に固定する (2026-10-22 に API が受け付けることを確認) | `jev-latest` は版が予告なく変わり、閾値の実測 ([game-rules.md](../game-rules.md)「Jev の閾値」) が無効になるため |
| 新しい属性と技 | どの属性も閾値に届かない時だけ、Claude に属性 1 つと、その属性の技 3 つ (master の 3 段階に合わせた威力・PP の範囲) を 1 件の定義として提案させる。技だけを新しく作る経路は置かない | 属性ごとの技の選択は Jev の Choice で、Choice は「当てはまらない」を返さない (`~/.claude/skills/jev/references/question-design-findings.md`「Choice は必ず何かを選ぶ」)。master の属性は 3 段階の技をすべて持つため、属性が決まれば技は必ずある |

## 改訂 (2026-10-28)

bannzai が、切り出しをクライアントでできるところまでにし、iPhone は写真の長押しで被写体を切り出す OS の機能の API をそのまま使い、それ以外は crop でよいと決めた ([DIRECTION.md](../DIRECTION.md)「決めたこと」2026-10-28、 https://github.com/bannzai/snapmon/issues/68 )。本番の通しの確認で生成に 25 秒かかり (Functions のインスタンスの起動と推論)、切り出せない写真のエラーが生成数を減らすため。上の比較の表の「端末内の OS の機能」の行の短所 (Web に同等の機能が無い) は、Web を crop にすることで受け入れた。

| 項目 | 決定 | 根拠 |
| --- | --- | --- |
| マスクを作る場所 | 端末だけ。サーバーはマスクを作らず、送られたマスクを検査済みの元の写真に当てる (切り出しの適用をサーバーが行う点は変えない) | bannzai の決定 |
| iOS 17 以降 | Vision の `VNGenerateForegroundInstanceMaskRequest` で前景のマスクを作り、`VNInstanceMaskObservation.generateScaledMaskForImage(forInstances:from:)` に全部の前景 (`allInstances`) を渡して、写真と同じ大きさのマスクにする。8 bit グレースケールの PNG にして `maskPath` で送る (`ios/Runner/AppDelegate.swift` の platform channel `snapmon/subject_mask`)。前景が無ければ crop に倒す | 公式ドキュメント: https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest (Availability: iOS 17.0+。"A request that generates an instance mask of noticable objects to separate from the background.")、 https://developer.apple.com/documentation/vision/vninstancemaskobservation/generatescaledmaskforimage(forinstances:from:) (iOS 17.0+。"Creates a high-resolution mask where everything becomes transparent black, except for the instances you specify.")。2026-10-28 に確認 |
| iOS 16 以前・Android・Web と、前景が見つからない・Vision が失敗した時 | ユーザーが写真の上で正方形の枠を動かして範囲を決め、その内側を白にした矩形のマスクを送る (`lib/features/capture/square_crop_editor.dart`・`subject_mask.dart`)。Android の ML Kit の Subject Segmentation は使わない (bannzai の決定は「iPhone は OS の機能、それ以外は crop」) | bannzai の決定 |
| マスクの無い生成 | 写真全体を絵にする (開発者メニューの見本の写真で、OS の切り出しが使えない時)。マスクに被写体の画素が 1 つも無い時も写真全体にする | 切り出せない写真をエラーにしないため |
| 被写体なしの拒否 | やめる (`no_subject` を拒否の理由から外し、被写体の面積の下限 1% と手の範囲の上限 95% も外した) | crop は写真全体になり得るため。上限を外したことで、写真全体に近い絵を他人が見る (DIRECTION.md「決めたこと」2026-10-28 で受け入れた) |
| マスクの出どころの記録 | `generate` の data の `maskSource` (`ios_subject` / `crop`。マスク無しは省くか `none`) を、受け付けた時に生成のレコードの `maskSource` に書く | 経路ごとの生成の結果を後から比べるため |
| Functions の設定 | `generate` と再試行のタスクのメモリを 4 GiB から 1 GiB にし、CPU 2・同時に処理する要求 1 の指定を外した (firebase-functions の既定の CPU 1・同時に 80 要求)。onnxruntime-node・モデルの取得 (`fetch-segmentation-model.mjs`・firebase.json の predeploy・firebase-ci.yml)・`functions/models/` を消した | 推論が無くなり、常駐メモリの 2.6 GB (下の実測) が要らなくなった。1 GiB での本番のメモリの使用量は未実測で、デプロイ後に Cloud Run のメトリクスで見直す |

## 実測 (2026-10-22、開発用の Mac。M シリーズの CPU で onnxruntime-node 1.30.0・CPU の実行)

この節は改訂 (2026-10-28) より前の IS-Net の選定の記録で、IS-Net の比較と Functions の設定は今のコードでは使わない。長辺 1024px への縮小 (`downscalePhoto`) の決定だけは今も生きていて、Vision と `applyMask` の前に使う。

見本は Wikimedia Commons の CC0 / Public domain の写真を幅 640px にしたもの (出典の一覧は `functions/test/fixtures/calibration/photos/LICENSES.md`) と、単色の画像。

| モデル | 1 枚の推論 | 常駐メモリの最大 | 単色の写真の被写体の割合 | 物の写真の被写体の割合 | 輪郭 (目視) |
| --- | --- | --- | --- | --- | --- |
| isnet-general-use (1024 × 1024 入力) | 0.86〜1.1 秒 (初回 1.4〜2.3 秒) | 2.6 GB | 0% (出力の最大 0.013) | 5.0〜49% | 自転車のスポーク・カメラの細部まで分かれる |
| silueta (320 × 320) | 0.41〜0.6 秒 | 0.64 GB | 0% (最大 0.103) | 3.8〜43% | スポークの間を埋める |
| u2netp (320 × 320) | 0.10〜0.15 秒 | 0.59 GB | 0% (最大 0.003) | 2.8〜41% | スポークの間を埋め、輪郭がにじむ |

端末の写真の大きさ (12 MP 前後) でも測った。見本 08 を 4000 × 3000 に拡大した JPEG (0.93 MB) をそのまま切り出すと、常駐メモリの最大が 3.3 GB、`art.png` が 6.45 MB になった。長辺 1024px に縮めてから切り出すと 2.4 GB・0.86 MB (被写体の割合は同じ 30.5%) だったため、Vision と切り出しには長辺 1024px に縮めた写真を使う (`downscalePhoto`。クライアントの縮小に頼らず、サーバーで揃える)。

`generate` と再試行のタスクは、メモリ 4 GiB・CPU 2・同時に処理する要求 1 (`concurrency: 1`。2nd gen の既定は CPU 1 以上で 80 のため、推論が重なってメモリが足りなくなるのを防ぐ) にした。Cloud Run functions の CPU で同じ時間になるかは未実測 (デプロイ後に生成レコードの時刻とログで測る)。

## 1 体あたりの原価の見積もり

| 費目 | 見積もり | 根拠 |
| --- | --- | --- |
| Claude (被写体の説明) | 約 0.022 ドル (上限の目安 0.04 ドル) | **未実測**。手元に Claude API のキーが無く (本番は WIF で Functions からだけ呼べる。#24)、本番と同じシステムプロンプト・schema を `claude -p --safe-mode --model claude-opus-5-5 --effort low` で 17 枚に通した実測で、出力 559〜639 トークン (思考を含む)、入力は Claude Code の道具の定義を含めて約 6,000 トークン・`total_cost_usd` 平均 0.041 ドルだった。API で直接呼ぶ時の入力は、システムプロンプト (約 1,500 トークン) と画像 (640 × 427 の切り出しで約 360 トークン。 https://platform.claude.com/docs/en/build-with-claude/vision の「tokens = (width px * height px)/750」) で 2,000〜3,000 トークンと見て、Claude Opus 5.5 の単価 (入力 4 ドル・出力 20 ドル / 100 万トークン。claude-api skill のモデル表、2026-10-06 時点) から計算した |
| Jev (分類・同じ被写体の判定・属性とステータスの判定) | 約 0.0003 ドル | 較正の実測で 108 リクエストの入力が 248,993 トークン (1 リクエスト平均 約 2,300 トークン)。1 体で 2〜3 リクエスト × jev-1.13.0 の 42 ドル / 10 億トークン ( https://docs.typesafe.ai/models.md ) |
| Cloud Vision (SafeSearch・Face・Label) | 約 0.003 ドル (月 1,000 ユニットまでは無料) | Label と Face が 1,000 ユニットあたり 1.50 ドルずつ、SafeSearch は Label と同じリクエストなら無料 (ADR 0001「不適切な画像・人物」) |
| Functions の実行時間 | 約 0.001 ドル | 1 回 15 秒・2 vCPU・4 GiB と見て、request-based billing の CPU 0.000024 ドル / vCPU 秒・メモリ 0.0000025 ドル / GiB 秒 ( https://cloud.google.com/functions/pricing-overview の us-central1 の値。asia-northeast1 の値は未確認)。改訂 (2026-10-28) の後は 1 vCPU・1 GiB で、同じ単価と 15 秒なら約 0.0004 ドルになる (実行時間は未実測) |
| 合計 | **約 0.03 ドル** | Claude が大半を占める |

1 日の上限 (uid ごとに 20 回、全体で 1,000 回。`functions/src/generation/pipeline.ts`) は、この見積もりで全体の原価を 1 日 30 ドル前後に抑える値にした。本番の生成レコードは Claude と Jev の使用量 (`claudeUsages`・`jevInputTokens`) を残すため、公開後の最初の判定日にこの表を実測で置き換える。

## Consequences

- (改訂 (2026-10-28) で無効) Functions のデプロイが、178 MB のモデルを含むソースを上げるようになる。生成の待ち時間に、切り出しの推論とモデルの読み込みが加わる
- 改訂 (2026-10-28) の後: Functions のソースからモデルが無くなり、生成の待ち時間から推論が消える。代わりに iOS は端末で Vision を動かす時間、それ以外はユーザーが範囲を決める操作が生成の前に入る。Android で ML Kit の Subject Segmentation の方が良いと分かった時は、同じ `maskPath` で端末のマスクを送れば、サーバーの変更無しで足せる
- 改訂 (2026-10-28) の後: crop の範囲とマスク無しの絵には背景が写り、PvP と共有カードで元の写真の一部 (写真全体のこともある) を他人が見る
- master に「物の分類」(`subjectCategories`) と属性の説明 (`elementTypes[].description`) を足した。master の版 1 はまだ投入していない (deploy-functions.yml の実行が 0 件) ため、版を上げずに版 1 に足した
