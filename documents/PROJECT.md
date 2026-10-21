# snapmon の企画と要件

仮説・判定基準・必要な機能・決めたことは [DIRECTION.md](DIRECTION.md) が正で、このファイルは企画の背景と調査で分かった制約をまとめる。

## 企画

撮った写真の被写体がモンスターになってバトルするゲーム。カメラで撮った画像の被写体に、HP・攻撃・防御・特攻・素早さ・技・PP が割り当てられ、ターン制のバトルができる。

- 起票元: https://github.com/bannzai/IdeaMemo/issues/372
- 配信先: iOS / Android / Web (Flutter + Flame)。立ち上げ設定 https://github.com/bannzai/IdeaMemo/issues/372#issuecomment-6306523682 の `platform`
- 事前調査 (2026-10-21) の要点
  - 同じ発想の直接型アプリは 2026 年に少なくとも 8 本出ているが、App Store の評価はどれも 0〜5 件。名前もコンセプトも近い Web アプリ SnapMonster ( https://www.producthunt.com/products/snapmonster ) が稼働中
  - バーコード・絵からクリーチャーを作る隣接型は US で評価数千〜6 万件 (Draw Creatures 60,781 件、Animash 14,671 件、Warcodes 2,787 件)
  - 既存アプリのレビューに残る不満: 生成されたモンスターが被写体に似ていない、ステータスが勝敗に効かない・極端で不公平、生成したものがアップデートや機種変更で変わる・消える、すぐ飽きる、生成や保有に早い段階で課金の上限がある、不適切な画像が生成されて他のユーザーに表示される

## 設計の制約

調査で分かった、機能の選び方によって効いてくる制約。どれを受け入れるかは DIRECTION.md の「決めたこと」に記録する。

- AI API の利用規約: Gemini API の追加利用規約は利用者を 18 歳以上とし、18 歳未満が使う、または使う可能性が高いサービスでの利用を禁止している ( https://ai.google.dev/gemini-api/terms )。Anthropic は未成年が触れる製品に年齢確認・コンテンツフィルタ等の安全策を求めている
- ストアの UGC 要件: App Store Review Guidelines 1.2 は AI content creation apps を対象に、不適切なコンテンツのフィルタ・通報・悪質なユーザーのブロック・連絡先の公開を必須にしている。Google Play も AI 生成コンテンツの通報機能を求めている
- 知的財産: ポケモンの名称・外見・固有の技名・タイプ相性表は使わない (App Review Guidelines 4.1・5.2.1)。任天堂がポケットペアを提訴した特許は「アイテムを投げてキャラクターを捕獲する・狙う・乗る」の機構 ( https://www.nintendo.co.jp/corporate/release/2024/240919.html )
- 個人情報: 本人を判別できる写真は個人情報に当たる (個人情報保護委員会 Q&A)。人物を被写体にした生成を他人に見せる機能は肖像権・いじめの問題になり得る
- Firebase: Cloud Storage for Firebase は 2026-02-03 から Blaze プラン (従量課金) が必須。Cloud Functions も Spark プランでは使えない
- Web: オンデバイス画像分類 (ML Kit) の Flutter プラグインは Web 非対応。Flutter Web のカメラは HTTPS が必要
