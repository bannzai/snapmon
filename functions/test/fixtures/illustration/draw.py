"""紙にクレヨンで描いた絵を机の上で撮った写真に似せた画像を描く (イラストの被写体の説明の検証用)。"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 1200, 900


def wobble(points, rng, amount=4.0):
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points]


def crayon_line(draw, points, color, rng, width=7, passes=3):
    for _ in range(passes):
        draw.line(wobble(points, rng, 3), fill=color, width=width, joint="curve")


def crayon_fill(draw, box, color, rng, density=0.9):
    x0, y0, x1, y1 = box
    y = y0
    while y < y1:
        if rng.random() < density:
            draw.line([(x0 + rng.uniform(0, 8), y + rng.uniform(-2, 2)), (x1 - rng.uniform(0, 8), y + rng.uniform(-2, 2))], fill=color, width=5)
        y += 6


def ellipse_points(cx, cy, rx, ry, n=48, start=0.0, end=2 * math.pi):
    return [(cx + rx * math.cos(start + (end - start) * i / n), cy + ry * math.sin(start + (end - start) * i / n)) for i in range(n + 1)]


def paper_and_table(rng):
    image = Image.new("RGB", (W, H), (150, 108, 72))
    draw = ImageDraw.Draw(image)
    for y in range(0, H, 3):
        tone = 140 + int(18 * math.sin(y / 23.0)) + rng.randint(-6, 6)
        draw.line([(0, y), (W, y)], fill=(tone, int(tone * 0.72), int(tone * 0.48)))
    paper = Image.new("RGBA", (900, 700), (246, 243, 232, 255))
    paper_draw = ImageDraw.Draw(paper)
    for _ in range(4000):
        x, y = rng.randint(0, 899), rng.randint(0, 699)
        g = rng.randint(232, 250)
        paper_draw.point((x, y), fill=(g, g - 2, g - 10, 255))
    return image, paper


def finish(image, paper, rng, angle):
    rotated = paper.rotate(angle, expand=True, resample=Image.BICUBIC)
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), mask=rotated.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    ox, oy = (W - rotated.width) // 2, (H - rotated.height) // 2
    image.paste(shadow, (ox + 14, oy + 18), shadow)
    image.paste(rotated, (ox, oy), rotated)
    return image.filter(ImageFilter.GaussianBlur(0.6))


def cake(paper, rng, sponge, cream, fruit, candle):
    d = ImageDraw.Draw(paper)
    cx = 450
    crayon_fill(d, (250, 360, 650, 560), sponge, rng)
    crayon_fill(d, (250, 330, 650, 370), cream, rng)
    crayon_fill(d, (250, 450, 650, 470), cream, rng)
    crayon_line(d, [(250, 330), (250, 560), (650, 560), (650, 330), (250, 330)], (60, 40, 30), rng)
    for x in range(290, 640, 80):
        crayon_line(d, ellipse_points(x, 315, 22, 20), fruit, rng, width=9)
        crayon_fill(d, (x - 16, 300, x + 16, 330), fruit, rng)
    for x in (330, 450, 570):
        crayon_fill(d, (x - 10, 200, x + 10, 300), candle, rng)
        crayon_line(d, ellipse_points(x, 180, 12, 22), (250, 160, 30), rng, width=6)
    crayon_line(d, [(200, 580), (700, 580)], (120, 120, 140), rng, width=6)


def ghost(paper, rng):
    d = ImageDraw.Draw(paper)
    body = ellipse_points(450, 300, 160, 150, start=math.pi, end=2 * math.pi)
    body += [(610, 300), (610, 540), (570, 510), (530, 545), (490, 510), (450, 545), (410, 510), (370, 545), (330, 510), (290, 540), (290, 300)]
    d.polygon(body, fill=(255, 255, 255))
    crayon_line(d, body, (70, 60, 120), rng)
    for ex in (395, 505):
        crayon_line(d, ellipse_points(ex, 320, 18, 26), (20, 20, 30), rng, width=8)
        crayon_fill(d, (ex - 12, 300, ex + 12, 340), (20, 20, 30), rng)
    crayon_line(d, ellipse_points(450, 400, 34, 18, start=0, end=math.pi), (220, 70, 90), rng, width=8)
    for sx, sy in ((180, 160), (720, 220), (700, 520)):
        crayon_line(d, [(sx - 20, sy), (sx + 20, sy)], (240, 190, 40), rng, width=6)
        crayon_line(d, [(sx, sy - 20), (sx, sy + 20)], (240, 190, 40), rng, width=6)


def main():
    kind, seed, output = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    rng = random.Random(seed)
    image, paper = paper_and_table(rng)
    if kind == "strawberry_cake":
        cake(paper, rng, sponge=(250, 200, 120), cream=(255, 250, 250), fruit=(225, 40, 50), candle=(90, 160, 230))
        angle = -4
    elif kind == "chocolate_cake":
        cake(paper, rng, sponge=(110, 70, 40), cream=(240, 200, 220), fruit=(140, 30, 140), candle=(240, 120, 160))
        angle = 5
    else:
        ghost(paper, rng)
        angle = 3
    finish(image, paper, rng, angle).save(output, quality=88)


if __name__ == "__main__":
    main()
