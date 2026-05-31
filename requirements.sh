#!/bin/bash
# requirements.sh - Dependency checks and installation for BuildProp scripts
# shellcheck shell=bash

# Partitions required for property extraction
declare -a PARTITIONS2EXTRACT=("product" "vendor" "vendor_dlkm" "system" "system_ext" "system_dlkm")

# Source utils if print_message is not yet available
[[ "$(type -t print_message)" == "function" ]] || { echo "[ERROR] utils.sh must be sourced before requirements.sh"; exit 1; }

# ---------------------------------------------------------------------------
# Core packages
# ---------------------------------------------------------------------------
install_packages "zip" "p7zip-full" "dos2unix" "aria2"

# Python 3
if ! command -v python3 &>/dev/null; then
  install_packages "python3"
fi

# pip
if ! python3 -m pip -V &>/dev/null; then
  print_message "pip not found — attempting to install via get-pip.py..." warning
  _pip_tmp="$(mktemp)"
  if curl -fsSL "https://bootstrap.pypa.io/get-pip.py" -o "$_pip_tmp"; then
    python3 "$_pip_tmp" &>/dev/null
    rm -f "$_pip_tmp"
  else
    print_message "Failed to download get-pip.py. Install pip manually: https://bootstrap.pypa.io/get-pip.py" error
  fi
fi

# payload_dumper (Android OTA payload extractor)
if ! command -v payload_dumper &>/dev/null; then
  print_message "payload_dumper not found — installing via pip..." info
  python3 -m pip install payload-dumper-go &>/dev/null \
    || python3 -m pip install payload_dumper &>/dev/null \
    || print_message "Could not install payload_dumper. Run: python3 -m pip install payload_dumper" error
fi

# ---------------------------------------------------------------------------
# imjtool (filesystem image tool)
# ---------------------------------------------------------------------------
if [[ ! -f "./imjtool" ]]; then
  print_message "imjtool not found — downloading..." info

  _imj_url="https://newandroidbook.com/tools/imjtool"
  _max_attempts=3
  _attempt=0

  while [[ ! -f "./imjtool" ]] && (( _attempt < _max_attempts )); do
    _attempt=$(( _attempt + 1 ))
    print_message "Downloading imjtool (attempt ${_attempt}/${_max_attempts})..." debug
    aria2c --file-allocation=none -q "$_imj_url" -d . -o imjtool && break
    sleep 2
  done

  if [[ ! -f "./imjtool" ]]; then
    print_message "Failed to download imjtool after ${_max_attempts} attempts. Download manually from: ${_imj_url}" error
  fi

  chmod +x ./imjtool
fi