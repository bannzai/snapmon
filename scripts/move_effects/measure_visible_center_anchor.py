"""技のエフェクトのスプライトシートの、全コマの見える範囲を合わせた矩形の中心を測る。

lib/features/battle/move_effect_sprite_sheets.dart の visibleCenterAnchor に入れる値を出す。
使い方: リポジトリのルートで python3 -I scripts/move_effects/measure_visible_center_anchor.py hit-spark sword-slash
引数は assets/images/move_effects/ のファイル名 (拡張子なし)。名前ごとに「名前<TAB>x<TAB>y」を小数第 3 位で出す。
読むだけで何も書かないため、繰り返し実行してよい。
"""

import json
import pathlib
import sys

from PIL import Image

# 見える画素とみなすアルファの下限。既存の 3 件 (#154) を測った時の基準に合わせる。
VISIBLE_ALPHA_THRESHOLD = 32

MOVE_EFFECTS_DIRECTORY = pathlib.Path("assets/images/move_effects")


def measure_visible_center_anchor(asset_name: str) -> tuple[float, float]:
    """asset_name のシートの全コマで、アルファが閾値以上の画素を囲む矩形の中心を、コマの幅・高さに対する割合で返す。

    見える画素が 1 つも無いシートは ValueError を投げる。
    """
    sprite_sheet_image = Image.open(MOVE_EFFECTS_DIRECTORY / f"{asset_name}.png").convert("RGBA")
    sprite_sheet_frames = json.loads((MOVE_EFFECTS_DIRECTORY / f"{asset_name}.json").read_text())["frames"]
    visible_left, visible_top, visible_right, visible_bottom = None, None, None, None
    for sprite_sheet_frame in sprite_sheet_frames:
        frame_rectangle = sprite_sheet_frame["frame"]
        bounding_box = (
            sprite_sheet_image.crop(
                (
                    frame_rectangle["x"],
                    frame_rectangle["y"],
                    frame_rectangle["x"] + frame_rectangle["w"],
                    frame_rectangle["y"] + frame_rectangle["h"],
                )
            )
            .getchannel("A")
            .point(lambda alpha: 255 if alpha >= VISIBLE_ALPHA_THRESHOLD else 0)
            .getbbox()
        )
        if bounding_box is None:
            continue
        visible_left = bounding_box[0] if visible_left is None else min(visible_left, bounding_box[0])
        visible_top = bounding_box[1] if visible_top is None else min(visible_top, bounding_box[1])
        visible_right = bounding_box[2] if visible_right is None else max(visible_right, bounding_box[2])
        visible_bottom = bounding_box[3] if visible_bottom is None else max(visible_bottom, bounding_box[3])
    if visible_left is None:
        raise ValueError(f"{asset_name}: 見える画素がありません")
    frame_width = sprite_sheet_frames[0]["sourceSize"]["w"]
    frame_height = sprite_sheet_frames[0]["sourceSize"]["h"]
    return (
        (visible_left + visible_right) / 2 / frame_width,
        (visible_top + visible_bottom) / 2 / frame_height,
    )


if __name__ == "__main__":
    for asset_name in sys.argv[1:]:
        anchor_x, anchor_y = measure_visible_center_anchor(asset_name)
        print(f"{asset_name}\t{anchor_x:.3f}\t{anchor_y:.3f}")
