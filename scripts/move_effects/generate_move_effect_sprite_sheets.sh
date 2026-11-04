#!/usr/bin/env bash
# 技のエフェクトのスプライトシート (assets/images/move_effects/) を PixelFX の固定のコミットから書き出す。
# 繰り返し実行してよい (取得済みのソースは使い回し、書き出した物とライセンスを上書きする)。
# 素材を増やす時は RENDER_TARGETS に足す。凍結・消滅などは素材の中に見本の人形を描くものがあり、--no-actor でも消えないため 1 つずつ目視で確かめる。
set -euo pipefail

PIXELFX_REPOSITORY_URL="https://github.com/patch-gg/pixelfx.git"
PIXELFX_COMMIT="a84159688af3ca37a4be05a0d422b94451b2e24e"
RENDER_TARGETS=("impacts/hit-spark" "melee/sword-slash" "lightning/zap-hit")

repository_root="$(git rev-parse --show-toplevel)"
source_directory="${repository_root}/tmp/pixelfx-source"
output_directory="${repository_root}/assets/images/move_effects"

if [ ! -d "${source_directory}/.git" ]; then
  git clone --filter=blob:none --no-checkout "${PIXELFX_REPOSITORY_URL}" "${source_directory}"
fi
git -C "${source_directory}" checkout --quiet --detach "${PIXELFX_COMMIT}"

(
  cd "${source_directory}"
  # --max と --zoom は確認用の contact.png だけに効き、同梱するシートには効かない
  node tools/render.mjs "${RENDER_TARGETS[@]}" --sheet --no-actor --max 8 --zoom 2
)

mkdir -p "${output_directory}"
for render_target in "${RENDER_TARGETS[@]}"; do
  effect_name="${render_target##*/}"
  cp "${source_directory}/records/${render_target}/${effect_name}.png" "${output_directory}/"
  cp "${source_directory}/records/${render_target}/${effect_name}.json" "${output_directory}/"
done
cp "${source_directory}/LICENSE" "${source_directory}/NOTICE.md" "${output_directory}/"
