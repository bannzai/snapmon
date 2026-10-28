"""snapmon のアプリアイコンを描き、iOS・Android・Web の置き場所に書き出す。

絵は紹介ページの画像 (docs/og.png) の印と同じ形 (黄緑の耳付きの輪に、生成りの顔) を、
documents/DIRECTION.md「デザインの方向」の色で描く。同じ入力から同じ画像を作るため、何度実行しても結果は変わらない。

使い方: リポジトリのルートで Pillow の入った python3 から実行する
    python3 scripts/app_icon/generate_app_icons.py
iOS は ios/Runner/Assets.xcassets/AppIcon.appiconset/ に 1024px の 1 枚 (single-size 形式) を置く。
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

# 色は lib/theme/snapmon_colors.dart の background・accent・card と同じ値
BACKGROUND = (0x15, 0x12, 0x1C)
ACCENT = (0xC6, 0xF4, 0x32)
CARD = (0xF4, 0xF1, 0xEA)

# 輪の外の半径を 1 とした時の印の各部の位置。docs/og.png の印 (輪の外の半径 170px) を測って割った値
INNER_RADIUS = 0.706
FACE_RADIUS = 0.5
EYE_OFFSET_X = 0.206
EYE_OFFSET_Y = -0.059
EYE_RADIUS = 0.1
# 左の耳の三角形 (先端・付け根の 2 点)。付け根は輪の帯 (半径 0.706〜1) の中に置き、輪から耳だけが突き出す形にする。右の耳は x を反転する
LEFT_EAR = [(-0.70, -1.15), (-0.80, -0.50), (-0.30, -0.80)]
# 印の上端 (耳の先) は輪の中心から -1.15、下端は +1.0 のため、輪の中心を印の縦の中央より 0.075 下げる
MARK_VERTICAL_SHIFT = 0.075

# 滑らかな縁にするため、この倍率で大きく描いてから縮める
SUPERSAMPLING = 4

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def draw_mark(size: int, ring_radius_ratio: float, background) -> Image.Image:
    """size 四方の画像に印を描いて返す。

    ring_radius_ratio は画像の一辺に対する輪の外の半径の比。background が None なら背景を透明にする (Android の adaptive icon の前景)。
    """
    canvas_size = size * SUPERSAMPLING
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0) if background is None else background + (255,))
    draw = ImageDraw.Draw(image)
    radius = canvas_size * ring_radius_ratio
    center_x = canvas_size / 2
    center_y = canvas_size / 2 + MARK_VERTICAL_SHIFT * radius

    def point(x: float, y: float):
        """輪の中心を原点・輪の外の半径を 1 とした座標 (x, y) の、画像の上の画素の位置を返す。"""
        return (center_x + x * radius, center_y + y * radius)

    def circle(x: float, y: float, circle_radius: float, color):
        """輪の半径を 1 とした座標 (x, y) を中心に、半径 circle_radius の円を color で塗る。"""
        left, top = point(x - circle_radius, y - circle_radius)
        right, bottom = point(x + circle_radius, y + circle_radius)
        draw.ellipse((left, top, right, bottom), fill=color)

    draw.polygon([point(x, y) for x, y in LEFT_EAR], fill=ACCENT)
    draw.polygon([point(-x, y) for x, y in LEFT_EAR], fill=ACCENT)
    circle(0, 0, 1.0, ACCENT)
    circle(0, 0, INNER_RADIUS, BACKGROUND)
    circle(0, 0, FACE_RADIUS, CARD)
    circle(-EYE_OFFSET_X, EYE_OFFSET_Y, EYE_RADIUS, BACKGROUND)
    circle(EYE_OFFSET_X, EYE_OFFSET_Y, EYE_RADIUS, BACKGROUND)
    smile_left, smile_top = point(-0.24, -0.02)
    smile_right, smile_bottom = point(0.24, 0.3)
    draw.arc(
        (smile_left, smile_top, smile_right, smile_bottom),
        start=25,
        end=155,
        fill=BACKGROUND,
        width=round(0.06 * radius),
    )
    return image.resize((size, size), Image.LANCZOS)


def save_opaque(image: Image.Image, path: Path):
    """App Store とストアの要件 (アイコンに透明を含めない) に合わせ、RGB で保存する。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path, optimize=True)


def save_transparent(image: Image.Image, path: Path):
    """透明を残したまま path に保存する (Android の adaptive icon の前景は、背景の色の上に重ねるため透明が要る)。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


# 輪の外の半径の比。全面に出すアイコンは 0.3 (印の縦が一辺の約 64%。docs/og.png の高さに対する印の比に近い)。
# 丸などで切り抜かれるアイコンは、印の端 (耳の先は画像の中心から約 1.29) が安全域の円に収まる比にする。
# Web の maskable の安全域は半径 40% (https://w3c.github.io/manifest/#icon-masks)、Android の adaptive icon の前景は
# 108dp のうち中央の直径 66dp (https://developer.android.com/develop/ui/views/launch/icon_design_adaptive) で半径 30.5%
FULL_BLEED_RATIO = 0.3
MASKABLE_RATIO = 0.3
ADAPTIVE_FOREGROUND_RATIO = 0.23
# 16px では細部が潰れるため印を大きくする (耳の先が端に触れない範囲)
FAVICON_RATIO = 0.36

ANDROID_LEGACY_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# adaptive icon の前景は 108dp
ANDROID_FOREGROUND_SIZES = {density: size * 108 // 48 for density, size in ANDROID_LEGACY_SIZES.items()}


def write_ios():
    """iOS の AppIcon.appiconset を、1024px の 1 枚 (single-size 形式) と Contents.json に置き換える。以前の大きさ別の PNG は消す。"""
    appiconset = REPOSITORY_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for old_icon in appiconset.glob("Icon-App-*.png"):
        old_icon.unlink()
    save_opaque(draw_mark(1024, FULL_BLEED_RATIO, BACKGROUND), appiconset / "AppIcon.png")
    contents = {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (appiconset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_android():
    """Android の密度ごとの従来のアイコン (ic_launcher) と adaptive icon の前景 (ic_launcher_foreground) を書き出す。"""
    resources = REPOSITORY_ROOT / "android/app/src/main/res"
    for density, size in ANDROID_LEGACY_SIZES.items():
        save_opaque(draw_mark(size, FULL_BLEED_RATIO, BACKGROUND), resources / f"mipmap-{density}/ic_launcher.png")
    for density, size in ANDROID_FOREGROUND_SIZES.items():
        save_transparent(
            draw_mark(size, ADAPTIVE_FOREGROUND_RATIO, None),
            resources / f"mipmap-{density}/ic_launcher_foreground.png",
        )


def write_web():
    """Web の favicon と、PWA の通常のアイコン・maskable のアイコン (192px・512px) を書き出す。"""
    web = REPOSITORY_ROOT / "web"
    save_opaque(draw_mark(16, FAVICON_RATIO, BACKGROUND), web / "favicon.png")
    for size in (192, 512):
        save_opaque(draw_mark(size, FULL_BLEED_RATIO, BACKGROUND), web / f"icons/Icon-{size}.png")
        save_opaque(draw_mark(size, MASKABLE_RATIO, BACKGROUND), web / f"icons/Icon-maskable-{size}.png")


if __name__ == "__main__":
    write_ios()
    write_android()
    write_web()
