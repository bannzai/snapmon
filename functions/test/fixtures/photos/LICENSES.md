# 生成の経路ごとのテスト写真の出典

`functions/scripts/probe-generation-paths.mjs` が生成の経路ごとに流す写真。どれも Wikimedia Commons の CC0 / Public domain の写真を幅 640px に縮小したもの。
経路と期待する結果は `expectations.json`。

- `ordinary/`・`same_subject/`・`same_kind/` は Jev の較正の見本 (`../calibration/photos/`、2026-10-22 に取得) をそのまま写した。同じ被写体・同じ種類の別の物の組は、較正のラベル (`../calibration/labels.json` の `dedupe.same`・`dedupe.differentSameKind`) と同じ組にした
- `person/`・`no_subject/` は 2026-10-28 に取得し、縮小の時にメタデータ (EXIF) を落とした

| ファイル | 元のファイル | ライセンス | 出典 |
| --- | --- | --- | --- |
| ordinary/mug.jpg | Coffee Mug (Unsplash).jpg (較正の 01.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Coffee_Mug_(Unsplash).jpg |
| ordinary/scissors.jpg | Crossed scissors.jpg (較正の 15.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Crossed_scissors.jpg |
| ordinary/cactus.jpg | Cactus (Unsplash).jpg (較正の 04.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Cactus_(Unsplash).jpg |
| ordinary/rubber_duck.jpg | Rubber duck in glass bowl crop.jpg (較正の 08.jpg) | Public domain | https://commons.wikimedia.org/wiki/File:Rubber_duck_in_glass_bowl_crop.jpg |
| ordinary/camera.jpg | Camera (Unsplash).jpg (較正の 12.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Camera_(Unsplash).jpg |
| same_subject/mug_another_shot.jpg | Coffee Mug (Unsplash).jpg (較正の 01b.jpg。01.jpg を反転・切り抜き・明るさの変更で作った別の写り方) | CC0 | https://commons.wikimedia.org/wiki/File:Coffee_Mug_(Unsplash).jpg |
| same_subject/scissors_another_shot.jpg | Crossed scissors.jpg (較正の 15b.jpg。15.jpg を反転・切り抜き・明るさの変更で作った別の写り方) | CC0 | https://commons.wikimedia.org/wiki/File:Crossed_scissors.jpg |
| same_kind/another_mug.jpg | Bucharest mug (Unsplash).jpg (較正の 02.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Bucharest_mug_(Unsplash).jpg |
| same_kind/another_rubber_duck.jpg | Duck Donuts Rubber Duck.jpg (較正の 09.jpg) | CC0 | https://commons.wikimedia.org/wiki/File:Duck_Donuts_Rubber_Duck.jpg |
| person/face_portrait.jpg | Face portrait (Unsplash).jpg | CC0 | https://commons.wikimedia.org/wiki/File:Face_portrait_(Unsplash).jpg |
| person/portrait.jpg | Portrait (Unsplash).jpg | CC0 | https://commons.wikimedia.org/wiki/File:Portrait_(Unsplash).jpg |
| person/holding_tulips.jpg | Woman holding a bouquet of tulips (Rawpixel.com 2017-04-27 Unsplash pgi0LPOM FI).jpg (顔が写らず、体と手と花束が写る) | CC0 | https://commons.wikimedia.org/wiki/File:Woman_holding_a_bouquet_of_tulips_(Rawpixel.com_2017-04-27_Unsplash_pgi0LPOM_FI).jpg |
| no_subject/brick_wall.jpg | Red brick wall (Unsplash).jpg | CC0 | https://commons.wikimedia.org/wiki/File:Red_brick_wall_(Unsplash).jpg |
| no_subject/sky.jpg | Sky unsplash 1.jpg | CC0 | https://commons.wikimedia.org/wiki/File:Sky_unsplash_1.jpg |
| no_subject/grass.jpg | Green grass texture (Unsplash).jpg | CC0 | https://commons.wikimedia.org/wiki/File:Green_grass_texture_(Unsplash).jpg |

## 集めない写真: 不適切な画像

性的・暴力的な写真 (Cloud Vision の SafeSearch で `explicit_content` になる経路) は置かない。
リポジトリは public で、CC0 であっても不適切な画像を配ると利用者と閲覧者に見せることになるため。
SafeSearch の経路は、Vision の応答をモックにした Emulator のテスト (`functions/test/emulator/generate.test.ts`) で確かめる。
