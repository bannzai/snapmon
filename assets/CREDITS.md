# 素材のクレジット

見本の写真・絵のライセンスは `assets/samples/photos/LICENSES.md`・`assets/samples/art/LICENSES.md`、フォントのライセンスは各フォントの `OFL.txt` にある。

## 技のエフェクト (`assets/images/move_effects/`)

- 素材名: PixelFX の Hit spark (`impacts/hit-spark`)・Sword slash (`melee/sword-slash`)・Zap hit (`lightning/zap-hit`)
- 作者: Patch。3 素材とも、ソースの先頭に書かれているとおり Sprite Fusion のオープンソースのエフェクト (Hugo Duprez、MIT) を元にしている
- 入手先: https://github.com/patch-gg/pixelfx/tree/a84159688af3ca37a4be05a0d422b94451b2e24e
- ライセンス: MIT。著作権表示と許諾文の同梱が必要で、同じディレクトリの `LICENSE`・`NOTICE.md` を配布物に含め、アプリのライセンスの一覧 (`LicenseRegistry`。`lib/main.dart`) にも登録している
- 持ち込まない物: `gallery/fonts/PatchPixel-Regular.woff2` は MIT の対象外 (`NOTICE.md`)
- 書き出し: `scripts/move_effects/generate_move_effect_sprite_sheets.sh` (固定のコミットと書き出しのコマンドを持つ)
- 改変: 画像は書き出したまま変えていない。再生するアプリが、時間を 0.5 秒に縮め (`hitReactionSeconds`)、大きさを被弾したモンスターに合わせ、攻撃の向きに合わせて左右を反転する (`lib/features/battle/battle_field_game.dart`)
