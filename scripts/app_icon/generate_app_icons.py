"""snapmon のアプリアイコンを描き、iOS・Android・Web・Google Play のストア掲載 (fastlane/metadata/android) の置き場所に書き出す。

絵はタイトル画面のヒーロー (lib/features/title/title_screen.dart の TitleHeroPainter) のマグカップ
(切り出しの縁取り・目・稲妻付き) と同じ形を、同じ寸法 (170×170 の箱の座標) で描く。斜めの写真の枠・オーラは入れない
(小さいサイズで潰れるため)。同じ入力から同じ画像を作るため、何度実行しても結果は変わらない。
マグカップの形・色を変える時は TitleHeroPainter._paintMonster と揃える。

使い方: リポジトリのルートで Pillow の入った python3 から実行する (make app-icons でも同じ)
    python3 scripts/app_icon/generate_app_icons.py
iOS は ios/Runner/Assets.xcassets/AppIcon.appiconset/ に 1024px の 1 枚 (single-size 形式) を置く。
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

# 色は lib/theme/snapmon_colors.dart の background・accent・textOnBackground と、TitleHeroPainter のマグカップの色と同じ値
BACKGROUND = (0x15, 0x12, 0x1C)
ACCENT = (0xC6, 0xF4, 0x32)
TEXT_ON_BACKGROUND = (0xF4, 0xF1, 0xEA)
MUG = (0x6D, 0x7B, 0x8A)
MUG_SHADE = (0x55, 0x60, 0x6E)

# 以下の座標は TitleHeroPainter._paintMonster の 170×170 の箱の座標 (左上が原点)
# 胴体の角丸の四角 (左, 上, 幅, 高さ) と、上・下の角の半径
BODY = (10, 30, 112, 120)
BODY_TOP_RADIUS = 16
BODY_BOTTOM_RADIUS = 44
# 胴体の外側の縁取り: 黄緑が胴体から 9 (線の幅 18 の半分)、その内側の地の色が 3 (線の幅 6 の半分)
ACCENT_OUTLINE_OFFSET = 9
BACKGROUND_OUTLINE_OFFSET = 3
# 胴体の右下の陰 (胴体をこれだけずらした形を胴体で切り抜く)
SHADE_SHIFT = (16, 18)
# 取っ手の半円の輪 (楕円の外接の四角 (左, 上, 幅, 高さ))。地の色の線 20 の上にマグカップの色の線 14 を重ねる
HANDLE = (119, 61, 38, 44)
HANDLE_STROKES = ((BACKGROUND, 20), (MUG, 14))
# 白目 (左, 上, 幅, 高さ) と、白目の左上に対する黒目の位置と大きさ
EYE_LEFTS = (36, 70)
EYE_TOP = 66
EYE_SIZE = (22, 26)
PUPIL = (10, 10, 9, 11)
# 稲妻 (モックの 24×28 の座標) と、箱の座標への移動・拡大
LIGHTNING = [(13, 1), (3, 16), (11, 16), (9, 27), (21, 10), (13, 10)]
LIGHTNING_TRANSLATE = (118, -6)
LIGHTNING_SCALE = (40 / 24, 48 / 28)

# 絵全体 (縁取り・取っ手の線・稲妻を含む) の箱の座標での外接の四角。左は縁取り、右は取っ手の太い方の線、上は稲妻の先、下は縁取りで決まる
ART_LEFT = BODY[0] - ACCENT_OUTLINE_OFFSET
ART_RIGHT = HANDLE[0] + HANDLE[2] + max(width for _, width in HANDLE_STROKES) / 2
ART_TOP = LIGHTNING_TRANSLATE[1] + min(y for _, y in LIGHTNING) * LIGHTNING_SCALE[1]
ART_BOTTOM = BODY[1] + BODY[3] + ACCENT_OUTLINE_OFFSET
ART_WIDTH = ART_RIGHT - ART_LEFT
ART_HEIGHT = ART_BOTTOM - ART_TOP
# 外接の四角の中心から角までの距離 (丸く切り抜かれるアイコンで、この円が安全域に収まる大きさにする)
ART_HALF_DIAGONAL = math.hypot(ART_WIDTH, ART_HEIGHT) / 2

# 滑らかな縁にするため、この倍率で大きく描いてから縮める
SUPERSAMPLING = 4
# 角丸を折れ線で近似する時の 1 つの角の分割数 (1024px を 4 倍で描いても折れ目が見えない数)
CORNER_SEGMENTS = 32

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def rounded_rect_points(left: float, top: float, right: float, bottom: float, top_radius: float, bottom_radius: float):
    """上の 2 つの角の半径が top_radius、下の 2 つが bottom_radius の角丸の四角の輪郭の点を返す。"""
    points = []
    for corner_x, corner_y, radius, start_degree in (
        (right - top_radius, top + top_radius, top_radius, -90),
        (right - bottom_radius, bottom - bottom_radius, bottom_radius, 0),
        (left + bottom_radius, bottom - bottom_radius, bottom_radius, 90),
        (left + top_radius, top + top_radius, top_radius, 180),
    ):
        for step in range(CORNER_SEGMENTS + 1):
            angle = math.radians(start_degree + 90 * step / CORNER_SEGMENTS)
            points.append((corner_x + radius * math.cos(angle), corner_y + radius * math.sin(angle)))
    return points


def draw_mug(size: int, art_width_ratio: float, background) -> Image.Image:
    """size 四方の画像の中央に、幅が一辺の art_width_ratio 倍のマグカップを描いて返す。

    background が None なら背景を透明にする (Android の adaptive icon の前景)。
    """
    canvas_size = size * SUPERSAMPLING
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0) if background is None else background + (255,))
    draw = ImageDraw.Draw(image)
    scale = canvas_size * art_width_ratio / ART_WIDTH
    origin_x = canvas_size / 2 - (ART_LEFT + ART_WIDTH / 2) * scale
    origin_y = canvas_size / 2 - (ART_TOP + ART_HEIGHT / 2) * scale

    def point(x: float, y: float):
        """箱の座標 (x, y) の、画像の上の画素の位置を返す。"""
        return (origin_x + x * scale, origin_y + y * scale)

    def body_polygon(offset: float, shift=(0, 0)):
        """胴体を外側に offset だけ広げ、shift だけずらした形の、画像の上の輪郭の点を返す。"""
        left, top, width, height = BODY
        return [
            point(x + shift[0], y + shift[1])
            for x, y in rounded_rect_points(
                left - offset,
                top - offset,
                left + width + offset,
                top + height + offset,
                BODY_TOP_RADIUS + offset,
                BODY_BOTTOM_RADIUS + offset,
            )
        ]

    def oval(left: float, top: float, width: float, height: float, color):
        """箱の座標の外接の四角 (left, top, width, height) の楕円を color で塗る。"""
        draw.ellipse((*point(left, top), *point(left + width, top + height)), fill=color)

    draw.polygon(body_polygon(ACCENT_OUTLINE_OFFSET), fill=ACCENT)
    draw.polygon(body_polygon(BACKGROUND_OUTLINE_OFFSET), fill=BACKGROUND)
    draw.polygon(body_polygon(0), fill=MUG)
    # 陰は胴体とずらした胴体の重なりだけを塗る
    body_mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(body_mask).polygon(body_polygon(0), fill=255)
    shade_mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(shade_mask).polygon(body_polygon(0, shift=SHADE_SHIFT), fill=255)
    image.paste(MUG_SHADE + (255,), (0, 0), ImageChops.multiply(body_mask, shade_mask))
    # Pillow の arc の線は外接の四角の内側に太るため、線の幅の半分だけ広げた四角で、線の中心を元の楕円に合わせる
    handle_left, handle_top, handle_width, handle_height = HANDLE
    for color, stroke_width in HANDLE_STROKES:
        half = stroke_width / 2
        draw.arc(
            (
                *point(handle_left - half, handle_top - half),
                *point(handle_left + handle_width + half, handle_top + handle_height + half),
            ),
            start=-90,
            end=90,
            fill=color,
            width=round(stroke_width * scale),
        )
    pupil_x, pupil_y, pupil_width, pupil_height = PUPIL
    for eye_left in EYE_LEFTS:
        oval(eye_left, EYE_TOP, *EYE_SIZE, TEXT_ON_BACKGROUND)
        oval(eye_left + pupil_x, EYE_TOP + pupil_y, pupil_width, pupil_height, BACKGROUND)
    draw.polygon(
        [
            point(LIGHTNING_TRANSLATE[0] + x * LIGHTNING_SCALE[0], LIGHTNING_TRANSLATE[1] + y * LIGHTNING_SCALE[1])
            for x, y in LIGHTNING
        ],
        fill=ACCENT,
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


def safe_zone_width_ratio(safe_radius_ratio: float) -> float:
    """絵の外接の四角の角が、画像の中心から一辺の safe_radius_ratio 倍の円に収まる時の、絵の幅の比を返す。"""
    return safe_radius_ratio * ART_WIDTH / ART_HALF_DIAGONAL


# 絵の幅の比。全面に出すアイコンは 0.72 (iOS の角丸の切り抜きでも、外接の四角の角にある取っ手・稲妻が欠けない大きさ。
# 1024px で角の空きは約 143px で、iOS のアイコンの角の半径の約 22% (225px) の円弧に掛かるのは絵の無い外接の四角の角だけ)。
# 丸などで切り抜かれるアイコンは、外接の四角の角が安全域の円に収まる比にする。
# Web の maskable の安全域は半径 40% (https://w3c.github.io/manifest/#icon-masks)、Android の adaptive icon の前景は
# 108dp のうち中央の直径 66dp (https://developer.android.com/develop/ui/views/launch/icon_design_adaptive) で半径 30.5%
FULL_BLEED_RATIO = 0.72
MASKABLE_RATIO = safe_zone_width_ratio(0.4)
ADAPTIVE_FOREGROUND_RATIO = safe_zone_width_ratio(0.305)
# 16px では細部が潰れるため絵を大きくする (取っ手の端が画像の端に触れない範囲)
FAVICON_RATIO = 0.9

ANDROID_LEGACY_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# adaptive icon の前景は 108dp
ANDROID_FOREGROUND_SIZES = {density: size * 108 // 48 for density, size in ANDROID_LEGACY_SIZES.items()}


def write_ios():
    """iOS の AppIcon.appiconset を、1024px の 1 枚 (single-size 形式) と Contents.json に置き換える。以前の大きさ別の PNG は消す。"""
    appiconset = REPOSITORY_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for old_icon in appiconset.glob("Icon-App-*.png"):
        old_icon.unlink()
    save_opaque(draw_mug(1024, FULL_BLEED_RATIO, BACKGROUND), appiconset / "AppIcon.png")
    contents = {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (appiconset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_android():
    """Android の密度ごとの従来のアイコン (ic_launcher) と adaptive icon の前景 (ic_launcher_foreground) を書き出す。"""
    resources = REPOSITORY_ROOT / "android/app/src/main/res"
    for density, size in ANDROID_LEGACY_SIZES.items():
        save_opaque(draw_mug(size, FULL_BLEED_RATIO, BACKGROUND), resources / f"mipmap-{density}/ic_launcher.png")
    for density, size in ANDROID_FOREGROUND_SIZES.items():
        save_transparent(
            draw_mug(size, ADAPTIVE_FOREGROUND_RATIO, None),
            resources / f"mipmap-{density}/ic_launcher_foreground.png",
        )


def write_web():
    """Web の favicon と、PWA の通常のアイコン・maskable のアイコン (192px・512px) を書き出す。"""
    web = REPOSITORY_ROOT / "web"
    save_opaque(draw_mug(16, FAVICON_RATIO, BACKGROUND), web / "favicon.png")
    for size in (192, 512):
        save_opaque(draw_mug(size, FULL_BLEED_RATIO, BACKGROUND), web / f"icons/Icon-{size}.png")
        save_opaque(draw_mug(size, MASKABLE_RATIO, BACKGROUND), web / f"icons/Icon-maskable-{size}.png")


# Google Play のストア掲載のアイコンの要件 (https://support.google.com/googleplay/android-developer/answer/9866151
# 「32-bit PNG (with alpha)」「Dimensions: 512px by 512px」)。fastlane の supply が読む locale ごとの images/icon.png に置く
GOOGLE_PLAY_ICON_SIZE = 512
GOOGLE_PLAY_LOCALES = ("ja-JP", "en-US")


def write_google_play():
    """Google Play のストア掲載のアイコン (512px) を、fastlane/metadata/android/<locale>/images/icon.png に書き出す。
    アルファを持つ PNG にし (Play の要件)、絵は全面に出す (Play はストアの表示で角を丸めるが、角に絵は無い)。"""
    for locale in GOOGLE_PLAY_LOCALES:
        save_transparent(
            draw_mug(GOOGLE_PLAY_ICON_SIZE, FULL_BLEED_RATIO, BACKGROUND),
            REPOSITORY_ROOT / f"fastlane/metadata/android/{locale}/images/icon.png",
        )


if __name__ == "__main__":
    write_ios()
    write_android()
    write_web()
    write_google_play()
