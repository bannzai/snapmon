"""紹介ページ (docs/index.html) に載せる画面の絵を、App Store のスクリーンショットから切り出して docs/images/ に書き出す。

スクリーンショット (fastlane/screenshots/ja/。描くのは store_screenshots/generate_store_screenshots_test.dart) は、
上にキャッチコピー、下に端末の枠と画面を描いた画像。紹介ページはキャッチコピーを HTML の見出しで書くため、
端末の枠と画面 (共有のページはカード) だけを切り出す。スクリーンショットの地の色は紹介ページの背景と同じ #15121c で、
切り出した画像はページの背景の上に置ける (WebP の圧縮で縁の色は #15111c 等に 1〜2 階調ずれる。2026-11-18 に書き出した
画像の縁の画素を数えて確かめた)。同じ入力から同じ画像を作るため、何度実行しても結果は変わらない。

使い方: スクリーンショットを作り直した時に、リポジトリのルートで Pillow の入った python3 から実行する
    python3 scripts/landing_page/crop_landing_page_images.py
"""

from pathlib import Path

from PIL import Image

# リポジトリのルート。実行した場所に関係なく、同じファイルを読み書きするために使う
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
# 切り出す元。紹介ページは日本語のため日本語の、いちばん画素の多い iPhone 6.9 インチ (1320×2868) のスクリーンショットを使う
SCREENSHOT_DIRECTORY = REPOSITORY_ROOT / "fastlane/screenshots/ja"
# 書き出す先。GitHub Pages が docs/ をそのまま配信する
OUTPUT_DIRECTORY = REPOSITORY_ROOT / "docs/images"

# 以下の四角 (左, 上, 右, 下) は 2026-11-17 に作り直したスクリーンショット (1320×2868) の画素を測った値。
# 端末の枠と影が入る四角。枠の外側は x 138〜1182・y 706〜2867、影は枠の外へ約 80px 広がり、キャッチコピーの下端は y 592 より上
DEVICE_BOX = (40, 610, 1280, 2868)
# 共有するカードが入る四角。カード (生成りの四角) は x 192〜1127・y 868〜2363 で、
# その下の紹介ページの URL の行 (y 2455 付近。ページの中に同じ URL を画像で重ねない) を入れない
SHARE_CARD_BOX = (170, 846, 1150, 2386)

# 書き出す画像の幅。ページで出す幅は最大 300 CSS px で、画素密度が 2 倍の画面で等倍になる
OUTPUT_WIDTH = 600
# WebP の品質。この値で 5 枚の合計は約 146KB で、書き出した画像を等倍で見て文字の輪郭のにじみが無いことを確かめた (2026-11-18)
WEBP_QUALITY = 86

# 書き出すファイルの名前 → (元のスクリーンショットのファイル名, 切り出す四角)
LANDING_PAGE_IMAGES = {
    "screen-capture.webp": ("iphone69_01_capture.png", DEVICE_BOX),
    "screen-born.webp": ("iphone69_02_born.png", DEVICE_BOX),
    "screen-dex.webp": ("iphone69_03_dex.png", DEVICE_BOX),
    "screen-battle.webp": ("iphone69_04_battle.png", DEVICE_BOX),
    "card-share.webp": ("iphone69_06_share.png", SHARE_CARD_BOX),
}


def write_landing_page_image(output_name, screenshot_name, crop_box):
    """スクリーンショット screenshot_name の crop_box の範囲を、幅 OUTPUT_WIDTH の WebP にして OUTPUT_DIRECTORY の output_name に上書きする。"""
    cropped = Image.open(SCREENSHOT_DIRECTORY / screenshot_name).convert("RGB").crop(crop_box)
    cropped.resize(
        (OUTPUT_WIDTH, round(cropped.height * OUTPUT_WIDTH / cropped.width)),
        Image.LANCZOS,
    ).save(OUTPUT_DIRECTORY / output_name, "WEBP", quality=WEBP_QUALITY, method=6)


def main():
    """LANDING_PAGE_IMAGES のすべての画像を書き出す。"""
    OUTPUT_DIRECTORY.mkdir(exist_ok=True)
    for output_name, (screenshot_name, crop_box) in LANDING_PAGE_IMAGES.items():
        write_landing_page_image(output_name, screenshot_name, crop_box)


if __name__ == "__main__":
    main()
