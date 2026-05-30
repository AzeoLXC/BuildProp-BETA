#!/bin/bash
# build_module.sh - Assemble the Magisk/KernelSU module zip from built prop files
# shellcheck shell=bash

# Source shared utilities
[ -f "utils.sh" ] && . ./utils.sh || { echo "[ERROR] utils.sh not found"; exit 1; }

# Process directories (enumerate or use explicit target from $1)
process_directories "${BASH_SOURCE[0]}" "$1"

# ---------------------------------------------------------------------------
# Load property files
# ---------------------------------------------------------------------------
EXT_PROP_FILES=$(find_prop_files "$dir")
# shellcheck disable=SC2086
EXT_PROP_CONTENT=$(cat $EXT_PROP_FILES)

# ---------------------------------------------------------------------------
# Derive module metadata
# ---------------------------------------------------------------------------
device_name=$(grep_prop                "ro.product.model"              "$EXT_PROP_CONTENT")
device_build_id=$(grep_prop            "ro.build.id"                   "$EXT_PROP_CONTENT")
device_codename=$(grep_prop            "ro.product.vendor.name"        "$EXT_PROP_CONTENT")
device_build_description=$(grep_prop   "ro.build.description"          "$EXT_PROP_CONTENT")
device_build_android_version=$(grep_prop "ro.vendor.build.version.release" "$EXT_PROP_CONTENT")
device_build_security_patch=$(grep_prop "ro.vendor.build.security_patch"   "$EXT_PROP_CONTENT")
device_codename="${device_codename^}"

base_name="${device_codename}_${device_build_id}"

# ---------------------------------------------------------------------------
# Assemble module directory
# ---------------------------------------------------------------------------
mkdir -p "result/$base_name/system/product/etc/"

cp "$dir"/{module,system}.prop "result/$base_name/"
cp -r "$dir/system/"           "result/$base_name/"
cp -r ./module/*               "result/$base_name/"

# ---------------------------------------------------------------------------
# Generate SHA-256 checksums for all scripts
# ---------------------------------------------------------------------------
cd "result/$base_name" || exit 1

find . -type f \( -name "*.sh" -o -name "update-binary" -o -name "updater-script" \) -print0 \
  | while IFS= read -r -d '' file; do
      [[ -f "$file" ]] && sha256sum "$file" | awk '{print $1}' >"$file.sha256"
    done

# ---------------------------------------------------------------------------
# Archive the module
# ---------------------------------------------------------------------------
zip -r -q "../../${base_name}.zip" .

cd ../..

# ---------------------------------------------------------------------------
# Compute and display module hash
# ---------------------------------------------------------------------------
module_hash=$(sha256sum "${base_name}.zip" | awk '{print $1}')
module_hash_upper=$(echo "$module_hash" | tr '[:lower:]' '[:upper:]')

print_message "Built module ${base_name}.zip (SHA256: ${module_hash_upper})" debug

# ---------------------------------------------------------------------------
# Emit GitHub Actions outputs
# ---------------------------------------------------------------------------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "module_base_name=${base_name}"
    echo "module_hash=${module_hash}"
    echo "device_name=${device_name}"
    echo "device_codename=${device_codename}"
    echo "device_build_id=${device_build_id}"
    echo "device_build_description=${device_build_description}"
    echo "device_build_android_version=${device_build_android_version}"
    echo "device_build_security_patch=${device_build_security_patch}"
  } >>"$GITHUB_OUTPUT"
fi