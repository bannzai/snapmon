---
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
---

# コーディング規約

- フィールド名・変数名は省略せず、長くても実態がわかる名前をつける (例: `atk` ではなく `attack`、`img` ではなく `sourceImage`)
- 関数の引数は原則 `{required}` の名前付き引数にし、呼び出し元にラベルが付くようにする
- コンストラクタの引数も nullable であっても `required` を付ける
- Flame の `Component` はゲーム画面の描画と入力だけを持ち、バトルの計算 (ダメージ・命中・行動順など) は Flutter・Flame に依存しない Dart の関数に置いて `flutter test` で単体テストする
- エラーメッセージは基本的にそのまま表示する (`e.toString()` の加工・プレフィックス除去等はしない)
