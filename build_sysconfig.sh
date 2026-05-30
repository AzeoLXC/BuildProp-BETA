#!/bin/bash
# build_sysconfig.sh - Copy Pixel Experience sysconfig XML files into the module tree
# shellcheck shell=bash

[ -f "utils.sh" ] && . ./utils.sh || { echo "[ERROR] utils.sh not found"; exit 1; }

process_directories "${BASH_SOURCE[0]}" "$1"

files_to_copy="nga pixel_experience_ google.xml google_build.xml google_fi.xml adaptivecharging.xml quick_tap.xml"

copy_specific_files \
  "$dir/extracted/product/etc/sysconfig" \
  "$dir/system/product/etc/sysconfig/" \
  "$files_to_copy"