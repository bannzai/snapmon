#!/usr/bin/env python3
"""PixelFX が書き出したスプライトシートを、アプリに同梱する形に整える。

引数はシートのディレクトリ (assets/images/move_effects)。ディレクトリの各 `<名前>.json` と同名の PNG について次を行い、PNG と JSON を上書きする。

1. コマを最大 `FRAME_COUNT_MAXIMUM` 個に間引く (等間隔に選び、最初と最後のコマは残す)。アプリは 1 回の被弾の時間 (0.5 秒) で全コマを再生するため、
   それより多いコマは見た目に効かず、サイズだけが増える (素材には 100〜300 コマのものがある)
2. 残したコマのアルファ 1 以上の画素を合わせた矩形で全コマを切り抜く (透明な余白を削る)。素材は画面全体 (320×180) の余白を持つものがあるため
3. 見える範囲の中心 (`meta.snapmon.visibleCenter`。アルファ 32 以上の画素を全コマで合わせた矩形の中心を、切り抜いた後のコマの幅・高さで割った値 0〜1) を書く。
   PixelFX の pivot は足元の原点で発光の位置と一致しないため、アプリはこの点を被弾したモンスターの中心に合わせる

繰り返し実行してよい (整えた後のシートに再び行っても、コマ数・矩形は変わらない)。
"""
import json
import sys
from pathlib import Path

from PIL import Image

FRAME_COUNT_MAXIMUM = 12
VISIBLE_ALPHA_MINIMUM = 32


def union_box(boxes):
    boxes = [box for box in boxes if box is not None]
    if not boxes:
        return None
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def process(json_path: Path) -> None:
    sheet_json = json.loads(json_path.read_text())
    pixelfx = sheet_json["meta"]["pixelfx"]
    frame_width, frame_height = pixelfx["frameSize"]
    columns = pixelfx["columns"]
    frame_count = pixelfx["frames"]
    image = Image.open(json_path.with_suffix(".png")).convert("RGBA")

    if frame_count <= FRAME_COUNT_MAXIMUM:
        kept_indexes = list(range(frame_count))
    else:
        kept_indexes = sorted({round(index * (frame_count - 1) / (FRAME_COUNT_MAXIMUM - 1)) for index in range(FRAME_COUNT_MAXIMUM)})
    frames = []
    for index in kept_indexes:
        x = (index % columns) * frame_width
        y = (index // columns) * frame_height
        frames.append(image.crop((x, y, x + frame_width, y + frame_height)))

    crop_box = union_box(frame.getchannel("A").point(lambda value: 255 if value > 0 else 0).getbbox() for frame in frames) or (
        0,
        0,
        frame_width,
        frame_height,
    )
    visible_box = union_box(
        frame.getchannel("A").point(lambda value: 255 if value >= VISIBLE_ALPHA_MINIMUM else 0).getbbox() for frame in frames
    )
    cropped = [frame.crop(crop_box) for frame in frames]
    new_width, new_height = cropped[0].size
    new_count = len(cropped)
    new_columns = min(new_count, max(1, round((new_count * new_height / new_width) ** 0.5)))
    new_rows = -(-new_count // new_columns)
    sheet = Image.new("RGBA", (new_columns * new_width, new_rows * new_height), (0, 0, 0, 0))
    frame_entries = []
    original_frames = sheet_json["frames"]
    name = json_path.stem
    for position, (index, frame) in enumerate(zip(kept_indexes, cropped)):
        x = (position % new_columns) * new_width
        y = (position // new_columns) * new_height
        sheet.alpha_composite(frame, (x, y))
        frame_entries.append(
            {
                "filename": f"{name} {position}",
                "frame": {"x": x, "y": y, "w": new_width, "h": new_height},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": new_width, "h": new_height},
                "sourceSize": {"w": new_width, "h": new_height},
                "duration": original_frames[index]["duration"],
            }
        )
    if visible_box is None:
        visible_center = (0.5, 0.5)
    else:
        visible_center = (
            round(((visible_box[0] + visible_box[2]) / 2 - crop_box[0]) / new_width, 3),
            round(((visible_box[1] + visible_box[3]) / 2 - crop_box[1]) / new_height, 3),
        )
    sheet_json["frames"] = frame_entries
    sheet_json["meta"]["size"] = {"w": sheet.width, "h": sheet.height}
    sheet_json["meta"]["frameTags"] = [{"name": name, "from": 0, "to": new_count - 1, "direction": "forward"}]
    pixelfx.update({"frames": new_count, "frameSize": [new_width, new_height], "columns": new_columns})
    sheet_json["meta"]["snapmon"] = {
        "visibleCenter": list(visible_center),
        "sourceFrames": pixelfx.get("sourceFrames", frame_count),
        "sourceFrameSize": pixelfx.get("sourceFrameSize", [frame_width, frame_height]),
    }
    sheet.save(json_path.with_suffix(".png"), optimize=True)
    json_path.write_text(json.dumps(sheet_json, indent=1) + "\n")
    print(f"{name}: {frame_count}→{new_count} frames, {frame_width}x{frame_height}→{new_width}x{new_height}, center {visible_center}")


def main() -> None:
    for json_path in sorted(Path(sys.argv[1]).glob("*.json")):
        process(json_path)


if __name__ == "__main__":
    main()
