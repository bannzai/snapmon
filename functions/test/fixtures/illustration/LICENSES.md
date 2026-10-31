# イラストの見本

紙にクレヨンで描いた絵を机の上で撮った写真に似せた画像。被写体の説明が媒体 (紙) ではなく描かれた物になるかを確かめるために使う (https://github.com/bannzai/snapmon/issues/129 )。

| ファイル | 中身 | 出典 |
| --- | --- | --- |
| `strawberry_cake.jpg` | いちごのショートケーキの絵 | agent が `draw.py` (Pillow) で描いた。CC0 |
| `chocolate_cake.jpg` | チョコレートケーキの絵 (`strawberry_cake.jpg` と同じ種類の別の絵) | 同上 |
| `ghost.jpg` | おばけの絵 | 同上 |

- 描き直す: `python3 draw.py <strawberry_cake | chocolate_cake | ghost> <seed> <出力のパス>` (seed は上から 1・2・3)
- `descriptions.json`: 本番と同じシステムプロンプトと schema を `claude -p` (`--model claude-opus-5-5 --effort low --safe-mode`) に通して書かせた説明 (1 回目)。`functions/test/emulator/generate.test.ts` が Claude のモックの答えに使う
- `result-2026-10-31.json`: 変更前 (head) と変更後 (new) のプロンプトで書かせた説明と、その説明を本番と同じ問いの組み立てで Jev (`jev-1.13.0`) に送った属性の確率・同じ被写体の判定。要約は `documents/game-rules.md`「被写体の説明」
