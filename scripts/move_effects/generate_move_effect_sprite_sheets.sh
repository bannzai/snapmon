#!/usr/bin/env bash
# 技のエフェクトのスプライトシート (assets/images/move_effects/) を PixelFX の固定のコミットから書き出す。
# 書き出す素材は master (assets/master/master.json) の effects のうち `spriteSheet` を持つ項目の `pixelfxID` で、master が正。
# 繰り返し実行してよい (取得済みのソースは使い回し、書き出した物とライセンスを上書きし、master から参照が消えたシートは tmp/move_effects-stale/ へ退避する)。
# 書き出した後、scripts/move_effects/postprocess_sprite_sheets.py でコマの間引き・余白の切り抜き・見える範囲の中心の記録を行う (理由は同スクリプトのヘッダー)。
# 素材の中に見本の人形を描くもの (status/poisoned 等) は --no-actor でも消えないため、素材を足した時は書き出した PNG を目視で確かめる。
set -euo pipefail

PIXELFX_REPOSITORY_URL="https://github.com/patch-gg/pixelfx.git"
PIXELFX_COMMIT="a84159688af3ca37a4be05a0d422b94451b2e24e"

repository_root="$(git rev-parse --show-toplevel)"
source_directory="${repository_root}/tmp/pixelfx-source"
output_directory="${repository_root}/assets/images/move_effects"
stale_directory="${repository_root}/tmp/move_effects-stale"
master_file="${repository_root}/assets/master/master.json"

if [ ! -d "${source_directory}/.git" ]; then
  git clone --filter=blob:none --no-checkout "${PIXELFX_REPOSITORY_URL}" "${source_directory}"
fi
(
  cd "${source_directory}"
  git checkout --quiet --detach "${PIXELFX_COMMIT}"
)

render_targets=()
while IFS= read -r render_target; do
  render_targets+=("${render_target}")
done < <(python3 -I -c '
import json, sys
master = json.load(open(sys.argv[1]))
print("\n".join(sorted({effect["pixelfxID"] for effect in master["effects"] if effect.get("spriteSheet")})))
' "${master_file}")

(
  cd "${source_directory}"
  # --max と --zoom は確認用の contact.png だけに効き、同梱するシートには効かない
  node tools/render.mjs "${render_targets[@]}" --sheet --no-actor --max 8 --zoom 2
)

mkdir -p "${output_directory}" "${stale_directory}"
for existing in "${output_directory}"/*.png; do
  [ -e "${existing}" ] || continue
  effect_name="$(basename "${existing}" .png)"
  if ! printf '%s\n' "${render_targets[@]}" | grep -q "/${effect_name}\$"; then
    mv "${existing}" "${output_directory}/${effect_name}.json" "${stale_directory}/"
  fi
done
for render_target in "${render_targets[@]}"; do
  effect_name="${render_target##*/}"
  cp "${source_directory}/records/${render_target}/${effect_name}.png" "${output_directory}/"
  cp "${source_directory}/records/${render_target}/${effect_name}.json" "${output_directory}/"
done
cp "${source_directory}/LICENSE" "${source_directory}/NOTICE.md" "${output_directory}/"

python3 -I "${repository_root}/scripts/move_effects/postprocess_sprite_sheets.py" "${output_directory}"
