"""紙にクレヨンで描いた絵を机の上で撮った写真に似せた画像を描く (イラストの被写体の説明の検証用。LICENSES.md)。

使い方: python3 draw.py <strawberry_cake | chocolate_cake | ghost> <seed> <出力のパス>
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

# 画像の大きさ。スマホの横長の写真と同じ 4:3 にし、fixture のファイルが較正の見本の写真 (functions/test/fixtures/calibration/photos/ の 18〜183 KB) と同じ程度になる大きさにした
IMAGE_WIDTH, IMAGE_HEIGHT = 1200, 900
# 机に置いた紙の大きさ。画像の 4 辺に机が見える余白を残すため、画像より一回り小さくした
PAPER_SIZE = (900, 700)


def wobble(points, rng, amount=4.0):
    """手描きの揺れとして、各点を ±amount px だけずらした点の列を返す。"""
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points]


def crayon_line(paper_draw, points, color, rng, width=7, passes=3):
    """points を結ぶ線を、少しずつずらして passes 回重ねて描く (クレヨンの線のかすれに見せるため)。"""
    for _ in range(passes):
        paper_draw.line(wobble(points, rng, 3), fill=color, width=width, joint="curve")


def crayon_fill(paper_draw, box, color, rng, density=0.9):
    """box (x0, y0, x1, y1) を横線の塗りで埋める。density は各行を塗る確率で、塗り残しをクレヨンらしさにする。"""
    left, top, right, bottom = box
    y = top
    while y < bottom:
        if rng.random() < density:
            paper_draw.line([(left + rng.uniform(0, 8), y + rng.uniform(-2, 2)), (right - rng.uniform(0, 8), y + rng.uniform(-2, 2))], fill=color, width=5)
        y += 6


def ellipse_points(center_x, center_y, radius_x, radius_y, count=48, start=0.0, end=2 * math.pi):
    """楕円の start から end までの角度の弧を、count 等分した点の列で返す。"""
    return [
        (center_x + radius_x * math.cos(start + (end - start) * i / count), center_y + radius_y * math.sin(start + (end - start) * i / count))
        for i in range(count + 1)
    ]


def paper_and_table(rng):
    """木目の机の画像と、その上に置く生成りの紙 (RGBA) を返す。紙にはまだ何も描かない。"""
    image = Image.new("RGB", (IMAGE_WIDTH, IMAGE_HEIGHT), (150, 108, 72))
    table_draw = ImageDraw.Draw(image)
    for y in range(0, IMAGE_HEIGHT, 3):
        tone = 140 + int(18 * math.sin(y / 23.0)) + rng.randint(-6, 6)
        table_draw.line([(0, y), (IMAGE_WIDTH, y)], fill=(tone, int(tone * 0.72), int(tone * 0.48)))
    paper = Image.new("RGBA", PAPER_SIZE, (246, 243, 232, 255))
    paper_draw = ImageDraw.Draw(paper)
    for _ in range(4000):
        x, y = rng.randint(0, PAPER_SIZE[0] - 1), rng.randint(0, PAPER_SIZE[1] - 1)
        gray = rng.randint(232, 250)
        paper_draw.point((x, y), fill=(gray, gray - 2, gray - 10, 255))
    return image, paper


def finish(image, paper, angle):
    """paper を angle 度傾けて影を付け、image の中央に置いて返す。最後の弱いぼかしはカメラで撮った柔らかさに見せるため。"""
    rotated = paper.rotate(angle, expand=True, resample=Image.BICUBIC)
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), mask=rotated.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    offset_x, offset_y = (IMAGE_WIDTH - rotated.width) // 2, (IMAGE_HEIGHT - rotated.height) // 2
    image.paste(shadow, (offset_x + 14, offset_y + 18), shadow)
    image.paste(rotated, (offset_x, offset_y), rotated)
    return image.filter(ImageFilter.GaussianBlur(0.6))


def cake(paper, rng, sponge, cream, fruit, candle):
    """paper にろうそくの立ったケーキを描く。sponge・cream・fruit・candle はスポンジ・クリーム・上の果物・ろうそくの色。"""
    paper_draw = ImageDraw.Draw(paper)
    crayon_fill(paper_draw, (250, 360, 650, 560), sponge, rng)
    crayon_fill(paper_draw, (250, 330, 650, 370), cream, rng)
    crayon_fill(paper_draw, (250, 450, 650, 470), cream, rng)
    crayon_line(paper_draw, [(250, 330), (250, 560), (650, 560), (650, 330), (250, 330)], (60, 40, 30), rng)
    for x in range(290, 640, 80):
        crayon_line(paper_draw, ellipse_points(x, 315, 22, 20), fruit, rng, width=9)
        crayon_fill(paper_draw, (x - 16, 300, x + 16, 330), fruit, rng)
    for x in (330, 450, 570):
        crayon_fill(paper_draw, (x - 10, 200, x + 10, 300), candle, rng)
        crayon_line(paper_draw, ellipse_points(x, 180, 12, 22), (250, 160, 30), rng, width=6)
    crayon_line(paper_draw, [(200, 580), (700, 580)], (120, 120, 140), rng, width=6)


def ghost(paper, rng):
    """paper ににっこり笑うおばけと、まわりのきらきらを描く。"""
    paper_draw = ImageDraw.Draw(paper)
    body = ellipse_points(450, 300, 160, 150, start=math.pi, end=2 * math.pi)
    body += [(610, 300), (610, 540), (570, 510), (530, 545), (490, 510), (450, 545), (410, 510), (370, 545), (330, 510), (290, 540), (290, 300)]
    paper_draw.polygon(body, fill=(255, 255, 255))
    crayon_line(paper_draw, body, (70, 60, 120), rng)
    for eye_x in (395, 505):
        crayon_line(paper_draw, ellipse_points(eye_x, 320, 18, 26), (20, 20, 30), rng, width=8)
        crayon_fill(paper_draw, (eye_x - 12, 300, eye_x + 12, 340), (20, 20, 30), rng)
    crayon_line(paper_draw, ellipse_points(450, 400, 34, 18, start=0, end=math.pi), (220, 70, 90), rng, width=8)
    for sparkle_x, sparkle_y in ((180, 160), (720, 220), (700, 520)):
        crayon_line(paper_draw, [(sparkle_x - 20, sparkle_y), (sparkle_x + 20, sparkle_y)], (240, 190, 40), rng, width=6)
        crayon_line(paper_draw, [(sparkle_x, sparkle_y - 20), (sparkle_x, sparkle_y + 20)], (240, 190, 40), rng, width=6)


def main():
    """引数の絵の種類と seed で画像を描き、出力のパスに JPEG で保存する。"""
    kind, seed, output = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    rng = random.Random(seed)
    image, paper = paper_and_table(rng)
    # 紙の傾きは絵ごとに変え、同じ机の上で撮り直した写真どうしに見えないようにした
    if kind == "strawberry_cake":
        cake(paper, rng, sponge=(250, 200, 120), cream=(255, 250, 250), fruit=(225, 40, 50), candle=(90, 160, 230))
        angle = -4
    elif kind == "chocolate_cake":
        cake(paper, rng, sponge=(110, 70, 40), cream=(240, 200, 220), fruit=(140, 30, 140), candle=(240, 120, 160))
        angle = 5
    else:
        ghost(paper, rng)
        angle = 3
    # 品質 88: 3 枚のファイルが 84〜117 KB になり、較正の見本の写真と同じ程度の大きさに収まるため
    finish(image, paper, angle).save(output, quality=88)


if __name__ == "__main__":
    main()
