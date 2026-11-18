"""scripts/og_image/replace_og_logo.py のテスト。

本物の docs/og.png とヒラギノ角ゴシック W6 (macOS にだけある) は使わず、リポジトリに同梱した書体と、一時ディレクトリに
作った見本の画像・lib/app_display_name.dart で、名前の読み取り・文字の大きさの探索・画像の書き換えを確かめる。
Pillow の入った python3 で実行する: python3 scripts/test/test_replace_og_logo.py
"""

import hashlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image, ImageChops, ImageDraw, ImageFont

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts/og_image"))

import replace_og_logo  # noqa: E402

# CI (ubuntu) にも手元にもある、リポジトリに同梱した書体。ヒラギノ角ゴシック W6 の代わりに大きさの探索を確かめるのに使う
TEST_FONT_PATH = str(REPOSITORY_ROOT / "assets/fonts/zen_kaku_gothic_new/ZenKakuGothicNew-Bold.ttf")
# 見本の画像の地の色 (左上の画素)。docs/og.png と同じく、塗る四角をこの色で塗る
BACKGROUND_COLOR = (20, 16, 40)


def text_width(text: str, font_size: int) -> int:
    """TEST_FONT_PATH の font_size の大きさで text を描いた時の、文字の画素の幅を返す。"""
    left, _, right, _ = ImageFont.truetype(TEST_FONT_PATH, font_size).getbbox(text)
    return right - left


def fits(text: str, font_size: int) -> bool:
    """text を font_size で描くと、ロゴの左端 84 から右端の上限 668 (下の 2 行の長い方の右端) に収まるかを返す。"""
    return 84 + text_width(text, font_size) <= 668


def write_sample_og_image(path: Path):
    """docs/og.png と同じ 1200×630 の見本の画像を path に書く。塗る四角の外にも内にも、地の色と違う画素を置く。"""
    image = Image.new("RGB", (1200, 630), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(image)
    # 古いロゴの代わり (塗る四角の内側)
    draw.rectangle((84, 226, 619, 313), fill=(255, 255, 255))
    # 塗る四角の内側で、新しい名前の文字が掛からない左上・右下の隅。塗れば地の色に戻る
    draw.rectangle((60, 190, 70, 200), fill=(255, 255, 255))
    draw.rectangle((690, 318, 700, 328), fill=(255, 255, 255))
    # 下の 2 行の文言の代わり (塗る四角の下、上端 335)
    draw.rectangle((84, 335, 668, 420), fill=(250, 200, 60))
    # 右の絵の代わり (塗る四角の右、左端 710)
    draw.ellipse((710, 150, 1100, 540), fill=(90, 200, 120))
    # 塗る四角 (60, 190)〜(700, 328) の 4 つの辺と角のすぐ外の画素。四角の境目を 1 画素ずれて塗ると変わる
    for x, y in [(59, 189), (701, 329), (59, 328), (701, 190), (300, 189), (300, 329), (59, 250), (701, 250)]:
        image.putpixel((x, y), (200, 0, 0))
    image.save(path)


def write_app_display_name(repository_root: Path, dart_source: str):
    """repository_root/lib/app_display_name.dart に dart_source を書く。"""
    (repository_root / "lib").mkdir(parents=True, exist_ok=True)
    (repository_root / "lib/app_display_name.dart").write_text(dart_source)


class TemporaryRepositoryTestCase(unittest.TestCase):
    """一時ディレクトリをリポジトリのルートに見立て、replace_og_logo が読み書きする場所と書体を差し替えるテストの土台。"""

    def setUp(self):
        """一時ディレクトリを作り、REPOSITORY_ROOT・OG_IMAGE_PATH・LOGO_FONT_PATH をテストの間だけ差し替える。後片付けは addCleanup が行う。"""
        self.repository_root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repository_root)
        self.og_image_path = self.repository_root / "docs/og.png"
        self.og_image_path.parent.mkdir(parents=True)
        for name, value in [
            ("REPOSITORY_ROOT", self.repository_root),
            ("OG_IMAGE_PATH", self.og_image_path),
            ("LOGO_FONT_PATH", TEST_FONT_PATH),
        ]:
            patcher = mock.patch.object(replace_og_logo, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)


class AppDisplayNameTest(TemporaryRepositoryTestCase):
    """app_display_name が lib/app_display_name.dart の定数を読み、読めない時に止まることを確かめる。"""

    def test_reads_constant_value(self):
        write_app_display_name(self.repository_root, "const String appDisplayName = 'SnapMonster';\n")
        self.assertEqual(replace_og_logo.app_display_name(), "SnapMonster")

    def test_reads_constant_after_document_comment(self):
        write_app_display_name(
            self.repository_root,
            "/// 利用者に見せるアプリの名前 ('snapmon' から変えた)。\nconst String appDisplayName = 'SnapMonster';\n",
        )
        self.assertEqual(replace_og_logo.app_display_name(), "SnapMonster")

    def test_raises_when_constant_uses_double_quotes(self):
        write_app_display_name(self.repository_root, 'const String appDisplayName = "SnapMonster";\n')
        with self.assertRaisesRegex(ValueError, "appDisplayName の値を読み取れない"):
            replace_og_logo.app_display_name()

    def test_raises_when_constant_is_renamed(self):
        write_app_display_name(self.repository_root, "const String appName = 'SnapMonster';\n")
        with self.assertRaisesRegex(ValueError, "appDisplayName の値を読み取れない"):
            replace_og_logo.app_display_name()

    def test_raises_when_name_is_empty(self):
        write_app_display_name(self.repository_root, "const String appDisplayName = '';\n")
        with self.assertRaisesRegex(ValueError, "appDisplayName の値を読み取れない"):
            replace_og_logo.app_display_name()


class LogoFontTest(TemporaryRepositoryTestCase):
    """logo_font が幅 584 (84〜668) に収まる 108 以下で最も大きい文字の大きさを選ぶことを確かめる。"""

    def test_short_name_uses_max_font_size(self):
        self.assertTrue(fits("snap", 108))
        self.assertEqual(replace_og_logo.logo_font("snap").size, 108)

    def test_long_name_uses_largest_size_that_fits(self):
        font_size = replace_og_logo.logo_font("SnapMonster").size
        self.assertLess(font_size, 108)
        self.assertTrue(fits("SnapMonster", font_size))
        self.assertFalse(fits("SnapMonster", font_size + 1))

    def test_name_exactly_reaching_max_right_at_max_size_uses_max_size(self):
        with mock.patch.object(replace_og_logo, "LOGO_MAX_RIGHT", 84 + text_width("SnapMonster", 108)):
            self.assertEqual(replace_og_logo.logo_font("SnapMonster").size, 108)

    def test_name_one_pixel_over_max_right_at_max_size_uses_smaller_size(self):
        with mock.patch.object(replace_og_logo, "LOGO_MAX_RIGHT", 84 + text_width("SnapMonster", 108) - 1):
            self.assertEqual(replace_og_logo.logo_font("SnapMonster").size, 107)

    def test_empty_name_uses_max_font_size(self):
        # 幅 0 は収まる。app_display_name が空の名前を通さないため、replace_og_logo からはこの入力に届かない
        self.assertEqual(replace_og_logo.logo_font("").size, 108)

    def test_raises_when_no_size_fits(self):
        with self.assertRaisesRegex(ValueError, "収まる大きさが無い"):
            replace_og_logo.logo_font("SnapMonster" * 200)


class ReplaceOgLogoTest(TemporaryRepositoryTestCase):
    """replace_og_logo が塗る四角の中だけを書き換え、大きさを保ち、再実行で同じ画像になり、止まる時は画像に触れないことを確かめる。"""

    def setUp(self):
        """名前を SnapMonster にした lib/app_display_name.dart と見本の docs/og.png を書き、書き換える前の画像を original_image に持つ。"""
        super().setUp()
        write_app_display_name(self.repository_root, "const String appDisplayName = 'SnapMonster';\n")
        write_sample_og_image(self.og_image_path)
        self.original_image = Image.open(self.og_image_path).convert("RGB")

    def test_keeps_size_and_mode(self):
        replace_og_logo.replace_og_logo()
        with Image.open(self.og_image_path) as image:
            self.assertEqual(image.size, (1200, 630))
            self.assertEqual(image.mode, "RGB")

    def test_keeps_pixels_outside_erase_box(self):
        replace_og_logo.replace_og_logo()
        difference = ImageChops.difference(self.original_image, Image.open(self.og_image_path).convert("RGB"))
        # 塗る四角 (60, 190)〜(700, 328)。右端・下端の画素を含む
        erase_box_mask = Image.new("L", (1200, 630), 0)
        ImageDraw.Draw(erase_box_mask).rectangle((60, 190, 700, 328), fill=255)
        self.assertIsNone(Image.composite(Image.new("RGB", (1200, 630)), difference, erase_box_mask).getbbox())
        # 塗る四角の中は変わっている (古いロゴが消え、新しい名前が描かれた)
        self.assertIsNotNone(difference.getbbox())

    def test_erases_old_logo_with_background_color(self):
        replace_og_logo.replace_og_logo()
        replaced_image = Image.open(self.og_image_path).convert("RGB")
        # 左上の隅と右下の隅 (四角の右端 700・下端 328 の画素を含む)。四角を内側へ縮めると古いロゴの色が残る
        for corner_box in [(60, 190, 71, 201), (690, 318, 701, 329)]:
            self.assertEqual(replaced_image.crop(corner_box).getcolors(), [(11 * 11, BACKGROUND_COLOR)])

    def test_draws_logo_between_left_and_max_right(self):
        replace_og_logo.replace_og_logo()
        erase_box_image = Image.open(self.og_image_path).convert("RGB").crop((60, 190, 701, 329))
        logo_box = ImageChops.difference(erase_box_image, Image.new("RGB", erase_box_image.size, BACKGROUND_COLOR)).getbbox()
        self.assertIsNotNone(logo_box)
        # 左端は 84 より左に出ない。84 との一致は確かめない: Pillow の getbbox の左は文字の画素ではなく描く原点 (0) で、
        # 文字の画素は書体の左の余白の分 (2〜4 画素) 右から始まる (docs/og.png では 87)
        self.assertGreaterEqual(60 + logo_box[0], 84)
        # getbbox の右は最後の画素の 1 つ右のため、右端の上限 668 の画素まで描いてよい
        self.assertLessEqual(60 + logo_box[2], 669)

    def test_running_twice_writes_same_file(self):
        replace_og_logo.replace_og_logo()
        first_digest = hashlib.sha256(self.og_image_path.read_bytes()).hexdigest()
        replace_og_logo.replace_og_logo()
        self.assertEqual(hashlib.sha256(self.og_image_path.read_bytes()).hexdigest(), first_digest)

    def test_does_not_touch_image_when_name_is_unreadable(self):
        write_app_display_name(self.repository_root, "const String appName = 'SnapMonster';\n")
        original_bytes = self.og_image_path.read_bytes()
        with self.assertRaises(ValueError):
            replace_og_logo.replace_og_logo()
        self.assertEqual(self.og_image_path.read_bytes(), original_bytes)

    def test_does_not_touch_image_when_name_does_not_fit(self):
        write_app_display_name(self.repository_root, f"const String appDisplayName = '{'SnapMonster' * 200}';\n")
        original_bytes = self.og_image_path.read_bytes()
        with self.assertRaises(ValueError):
            replace_og_logo.replace_og_logo()
        self.assertEqual(self.og_image_path.read_bytes(), original_bytes)


if __name__ == "__main__":
    unittest.main()
