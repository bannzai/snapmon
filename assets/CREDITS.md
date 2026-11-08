# 素材のクレジット

見本の写真・絵のライセンスは `assets/samples/photos/LICENSES.md`・`assets/samples/art/LICENSES.md`、フォントのライセンスは各フォントの `OFL.txt` にある。

## 技のエフェクト (`assets/images/move_effects/`)

- 素材名: PixelFX の 167 素材。一覧は master (`assets/master/master.json`) の `effects` の `pixelfxId` (技ごとの割り当て) が正
- 作者: Patch。素材の一部 (hit-spark・sword-slash・zap-hit・splash・vine-whip・earth-spike・thorns・acid-splash・claw-swipe・fish-school・snowflake-burst・healing-bloom・emp-blast・firework-burst・fire-breath・confetti 等) は、ソースの先頭に書かれているとおり Sprite Fusion のオープンソースのエフェクト (Hugo Duprez、MIT) を元にしている
- 入手先: https://github.com/patch-gg/pixelfx/tree/a84159688af3ca37a4be05a0d422b94451b2e24e
- ライセンス: MIT。著作権表示と許諾文の同梱が必要で、同じディレクトリの `LICENSE`・`NOTICE.md` を配布物に含め、アプリのライセンスの一覧 (`LicenseRegistry`。`lib/main.dart`) にも登録している
- 持ち込まない物: `gallery/fonts/PatchPixel-Regular.woff2` は MIT の対象外 (`NOTICE.md`)。見本の人形を描く素材 (`status/poisoned` 等) は使わない
- 書き出し: `scripts/move_effects/generate_move_effect_sprite_sheets.sh` (固定のコミットと書き出しのコマンドを持つ)
- 改変: 書き出した後に `scripts/move_effects/postprocess_sprite_sheets.py` でコマを 12 個に間引き、透明な余白を切り抜いている (同梱の大きさを 121MB から 13MB にするため。絵の中身は変えていない)。再生するアプリが、時間を 0.5 秒に縮め (`hitReactionSeconds`)、大きさを被弾したモンスターに合わせ、攻撃の向きに合わせて左右を反転する (`lib/features/battle/battle_field_game.dart`)

## BGM (`assets/audio/`)

どの画面で流すかは `lib/audio/game_audio.dart` の `BackgroundMusic`。

- `song18_0.mp3` (タイトル・下タブの画面)
  - 素材名: Crystal Cave (song18)。作者: cynicmusic (The Cynic Project / pixelsphere.org)
  - 入手先: https://opengameart.org/content/crystal-cave-song18
  - ライセンス: CC0 (クレジット表記は不要。作者はページで pixelsphere.org / The Cynic Project のクレジットと、使った時の連絡を希望している)
  - 改変: 入手したファイルのまま
- `battleThemeA.mp3` (バトル画面)
  - 素材名: Battle Theme A。作者: cynicmusic (cynicmusic.com / pixelsphere.org)
  - 入手先: https://opengameart.org/content/battle-theme-a
  - ライセンス: CC0 (クレジット表記は不要)
  - 改変: Web の読み込みを軽くするため、274 kbps の元のファイルを ffmpeg で 96 kbps の MP3 に再エンコードした (`ffmpeg -i battleThemeA.mp3 -codec:a libmp3lame -b:a 96k -map_metadata -1`)。曲そのものは変えていない

## 効果音 (`assets/audio/`)

どの場面で鳴らすかは `lib/audio/game_audio.dart` の `SoundEffect`。

- 素材名: The Essential Retro Video Game Sound Effects Collection (512 sounds) のうち `sfx_sounds_damage1.wav` (技が当たった)・`sfx_sounds_negative2.wav` (倒れた)・`sfx_sounds_fanfare1.wav` (勝った)・`sfx_sounds_negative1.wav` (負けた)。作者: Juhani Junkala
- 入手先: https://opengameart.org/content/512-sound-effects-8-bit-style
- ライセンス: CC0 (クレジット表記は不要)
- 改変: 入手したファイルのまま (ファイル名も変えていない)
