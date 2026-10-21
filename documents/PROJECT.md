# snapmon の企画と要件

仮説・判定基準・必要な機能・決めたことは [DIRECTION.md](DIRECTION.md) が正で、このファイルは企画の背景と調査で分かった制約をまとめる。

## 企画

撮った写真の被写体がモンスターになってバトルするゲーム。カメラで撮った画像の被写体に、HP・攻撃・防御・特攻・素早さ・技・PP が割り当てられ、ターン制のバトルができる (起票時の案。特攻は作るかの判断の返答に無く、DIRECTION.md の「決めたこと」で実装では置かないと決めた)。

- 起票元: https://github.com/bannzai/IdeaMemo/issues/372
- 配信先: iOS / Android / Web (Flutter + Flame)。立ち上げ設定 https://github.com/bannzai/IdeaMemo/issues/372#issuecomment-6306523682 の `platform`
- 事前調査 (2026-10-21) の要点
  - 同じ発想の直接型アプリは 2026 年に少なくとも 8 本出ているが、App Store の評価はどれも 0〜5 件。名前もコンセプトも近い Web アプリ SnapMonster ( https://www.producthunt.com/products/snapmonster ) が稼働中
  - バーコード・絵からクリーチャーを作る隣接型は US で評価数千〜6 万件 (Draw Creatures 60,781 件、Animash 14,671 件、Warcodes 2,787 件)
  - 既存アプリのレビューに残る不満: 生成されたモンスターが被写体に似ていない、ステータスが勝敗に効かない・極端で不公平、生成したものがアップデートや機種変更で変わる・消える、すぐ飽きる、生成や保有に早い段階で課金の上限がある、不適切な画像が生成されて他のユーザーに表示される

## 設計の制約

調査で分かった、機能の選び方によって効いてくる制約。どれを受け入れるかは DIRECTION.md の「決めたこと」に記録する。

- AI API の利用規約: Gemini API の追加利用規約は「You must be 18 years of age or older to use the APIs」とし、18 歳未満が使う、または使う可能性が高いサービス ("directed towards or is likely to be accessed by individuals under the age of 18") での利用を禁止している ( https://ai.google.dev/gemini-api/terms 、2026-10-21 に確認)。Anthropic は未成年が直接触れる製品の組織に、年齢確認・コンテンツフィルタ・子どもの安全向けのシステムプロンプトなどの安全策と、AI と対話していることの開示 ("Organizations must disclose to their users that they are interacting with an AI system rather than a human") を求めている ( https://support.claude.com/en/articles/9307344-responsible-use-of-anthropic-s-models-guidelines-for-organizations-serving-minors )
- ストアの UGC 要件: App Store Review Guidelines 1.2 は対象に「AI content creation apps」を明記し、不適切なコンテンツのフィルタ・通報と懸念へのすみやかな対応・悪質なユーザーのブロック・連絡先の公開を求めている ( https://developer.apple.com/app-store/review/guidelines/ )。Google Play は、AI でコンテンツを生成するアプリにアプリを離れずに不快なコンテンツを通報・フラグできる機能を求め、公開 UGC があるアプリにはユーザーとコンテンツの通報、ユーザーのブロックを求めている ( https://support.google.com/googleplay/android-developer/answer/13985936 、 https://support.google.com/googleplay/android-developer/answer/9876937 )
- 知的財産: ポケモンの名称・外見・固有の技名・タイプ相性表は使わない。App Review Guidelines 4.1 は他社のブランド・製品名を許可なくアプリのアイコンや名前に使うことを、5.2.1 は商標・著作物を許可なく使うことを禁じている ( https://developer.apple.com/app-store/review/guidelines/ )。任天堂がポケットペアを提訴した特許は「アイテムを投げてキャラクターを捕獲する・狙う・乗る」の機構 ( https://www.nintendo.co.jp/corporate/release/2024/240919.html )
- 個人情報: 個人情報保護委員会の Q&A は、本人を判別できる写真は個人情報に当たるとしている ( https://www.ppc.go.jp/all_faq_index/faq1-q1-16/ 、 https://www.ppc.go.jp/all_faq_index/faq1-q7-11/ )。人物を被写体にした生成を他人に見せる機能が肖像権・いじめの問題になり得るのは agent の推測
- Firebase: Cloud Storage for Firebase は 2026-02-03 から Blaze プラン (従量課金) が必須 ( https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024 、2026-10-21 に確認)。Cloud Functions は料金表の Spark の欄が「Not applicable」で、Spark プランでは使えない ( https://firebase.google.com/pricing )
- Web: オンデバイス画像分類の Flutter プラグイン google_mlkit_image_labeling は Android・iOS だけに対応し、"Web or any other platform is not supported" としている ( https://pub.dev/packages/google_mlkit_image_labeling )。Flutter Web のカメラ (camera_web) は secure context (HTTPS、ローカル開発なら localhost) が必要 ( https://pub.dev/packages/camera_web )
