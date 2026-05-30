#!/bin/bash
# build_bootanimation.sh - Copy bootanimation media into the module tree
# shellcheck shell=bash

[ -f "utils.sh" ] && . ./utils.sh || { echo "[ERROR] utils.sh not found"; exit 1; }

process_directories "${BASH_SOURCE[0]}" "$1"

copy_specific_files \
  "$dir/extracted/product/media" \
  "$dir/system/product/media" \
  "bootanimation"