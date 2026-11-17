"""紹介ページの OGP 画像 (docs/og.png) の中のロゴの文字を、アプリの名前 (lib/app_display_name.dart) に描き直す。

docs/og.png を一から描くコードはリポジトリに無いため、ロゴの場所だけを地の色で塗ってから文字を描き、ほかの画素
(下の 2 行の文言・右の絵) には触れない。同じ入力から同じ画像を作るため、何度実行しても結果は変わらない。

使い方: macOS で、リポジトリのルートで Pillow の入った python3 から実行する
    python3 scripts/og_image/replace_og_logo.py
書体は macOS に入っているヒラギノ角ゴシック W6 を使う (リポジトリに同梱できないため、macOS 以外では実行できない)。
元の画像のロゴ「snapmon」の書体は記録が無く、手元の書体 9 種で同じ幅に描いて元の画素と比べ、差が最も小さかったものを選んだ
(https://github.com/bannzai/snapmon/issues/351 の PR に比べた結果がある)。
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OG_IMAGE_PATH = REPOSITORY_ROOT / "docs/og.png"
LOGO_FONT_PATH = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# 以下の座標は docs/og.png (1200×630) の画素の位置で、名前を変える前の画像を測った値
# (ロゴ「snapmon」の外接の四角は 84,226〜619,313、下の 2 行の上端は 335、右端は 668、右の絵の左端は 710)。
# ロゴを消すために塗る四角 (左, 上, 右, 下)。下の行 (上端 335) と右の絵 (左端 710) に掛からない範囲にする
LOGO_ERASE_BOX = (60, 190, 700, 328)
# ロゴの左端。元のロゴと下の 2 行の左端に揃える
LOGO_LEFT = 84
# ロゴの文字の下端 (ベースライン)。元のロゴ「snapmon」の、下に伸びない文字の下端 (p の下端 313 ではない) に揃える
LOGO_BASELINE = 292
# ロゴの右端の上限。下の 2 行のうち長い方の右端 (668) を超えず、右の絵との間を下の行と同じだけ空ける
LOGO_MAX_RIGHT = 668
# 元のロゴの文字の大きさ (ヒラギノ角ゴシック W6 で「snapmon」が元と同じ幅 535 になる大きさ)。名前が短ければこの大きさで描く
LOGO_MAX_FONT_SIZE = 108
LOGO_COLOR = (255, 255, 255)


def app_display_name() -> str:
    """lib/app_display_name.dart の定数 appDisplayName の値を返す。"""
    return re.search(
        r"const String appDisplayName = '([^']+)';",
        (REPOSITORY_ROOT / "lib/app_display_name.dart").read_text(),
    ).group(1)


def logo_font(text: str) -> ImageFont.FreeTypeFont:
    """text が LOGO_LEFT から LOGO_MAX_RIGHT の間に収まる、LOGO_MAX_FONT_SIZE 以下で最も大きい書体を返す。"""
    for font_size in range(LOGO_MAX_FONT_SIZE, 0, -1):
        font = ImageFont.truetype(LOGO_FONT_PATH, font_size)
        if LOGO_LEFT + font.getbbox(text)[2] - font.getbbox(text)[0] <= LOGO_MAX_RIGHT:
            return font
    raise ValueError(f"ロゴ「{text}」が幅 {LOGO_MAX_RIGHT - LOGO_LEFT} に収まる大きさが無い")


def replace_og_logo():
    """docs/og.png のロゴの場所を地の色 (画像の左上の画素の色) で塗り、アプリの名前を描いて上書き保存する。"""
    image = Image.open(OG_IMAGE_PATH).convert("RGB")
    draw = ImageDraw.Draw(image)
    draw.rectangle(LOGO_ERASE_BOX, fill=image.getpixel((0, 0)))
    text = app_display_name()
    font = logo_font(text)
    # anchor "ls" は文字の左端とベースラインを指定の位置に置く。左の余白 (getbbox の左) を引いて、文字の画素の左端を揃える
    draw.text((LOGO_LEFT - font.getbbox(text)[0], LOGO_BASELINE), text, font=font, fill=LOGO_COLOR, anchor="ls")
    image.save(OG_IMAGE_PATH, optimize=True)


if __name__ == "__main__":
    replace_og_logo()
