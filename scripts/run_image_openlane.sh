#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?run tag required}"

cd /home/vboxuser/BMSemi_SNN_image_comp

export PROJECT_ROOT="$PWD"
export PDK_ROOT=/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/dependencies/pdks
export PDK=sky130A
export CARAVEL_ROOT=/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/caravel

echo "$TAG" > /home/vboxuser/impact_runs/latest_image_harden_tag.txt
echo "Run tag: $TAG"
echo "Project: $PROJECT_ROOT"
echo "PDK_ROOT: $PDK_ROOT"
echo "CARAVEL_ROOT: $CARAVEL_ROOT"

/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/openlane/.venv/bin/python3 -m librelane \
  -m "$PROJECT_ROOT" \
  -m "$PDK_ROOT" \
  -m "$CARAVEL_ROOT" \
  -m "$HOME/.ipm" \
  --docker-no-tty \
  --dockerized \
  --run-tag "$TAG" \
  --manual-pdk \
  --pdk-root "$PDK_ROOT" \
  --pdk "$PDK" \
  --ef-save-views-to "$PROJECT_ROOT" \
  --overwrite \
  --hide-progress-bar \
  -j 4 \
  openlane/user_project_wrapper/config.json
