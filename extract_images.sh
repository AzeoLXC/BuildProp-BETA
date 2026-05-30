#!/bin/bash
# extract_images.sh - Download, extract, and build Pixel prop modules from OTA/factory images
# shellcheck shell=bash

[ -f "utils.sh" ] && . ./utils.sh || { echo "[ERROR] utils.sh not found"; exit 1; }

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------
readonly EI="./extracted_images"
readonly EAI="./extracted_archive_images"
readonly EI_BP="${EI##"./"}"
readonly EAI_BP="${EAI##"./"}"

# ---------------------------------------------------------------------------
# Step 1: Unpack downloaded ZIP archives → payload.bin or raw images
# ---------------------------------------------------------------------------
if [ -d "dl" ]; then
  print_message "Extracting images from downloaded OTA / factory archives..." info

  for file in ./dl/*; do
    [[ -f "${file:?}" && "${file: -4}" == ".zip" ]] || continue

    filename="${file##*/}"
    basename="${filename%.*}"

    print_message "Processing \"$filename\"..." info
    extraction_start=$(date +%s)

    if unzip -l "$file" | grep -q "payload.bin"; then
      print_message "OTA archive detected — extracting payload.bin..." debug

      if ! 7z e "$file" -o"$EAI" "payload.bin" -r &>/dev/null; then
        print_message "Failed to extract payload.bin from $file. Skipping..." warning
        continue
      fi

      mv -f "$EAI_BP/payload.bin" "$EAI/$basename.bin"
      print_message "Saved to \"$EAI/$basename.bin\"." debug
    else
      print_message "Factory image detected — extracting all contents..." debug

      if ! 7z e "$file" -o"$EAI_BP" -r -y &>/dev/null; then
        print_message "Failed to extract $file. Skipping..." warning
        continue
      fi
    fi

    rm -f "$file"

    extraction_end=$(date +%s)
    print_message "Extraction completed in $((extraction_end - extraction_start))s." debug
  done
fi

# ---------------------------------------------------------------------------
# Step 2: Dump partition images from payload.bin / nested ZIPs
# ---------------------------------------------------------------------------
if [ -d "$EAI_BP" ] && [ -n "$(ls -A "$EAI_BP"/*.{zip,bin} 2>/dev/null)" ]; then
  print_message "Dumping partition images from \"$EAI_BP\"..." info

  for file in "$EAI"/*.{zip,bin}; do
    [[ -f "${file:?}" && ("$file" == *.zip || "$file" == *.bin) ]] || continue

    filename="${file##*/}"
    basename="${filename%.*}"

    print_message "Processing \"$filename\"..." info
    extraction_start=$(date +%s)

    if [[ "${file: -4}" == ".bin" ]]; then
      # OTA payload — use payload_dumper
      partitionsArgs=$(IFS=,; echo "${PARTITIONS2EXTRACT[*]}")

      if ! payload_dumper "$file" --partitions="$partitionsArgs" --out="$EI_BP/$basename" 2>/dev/null; then
        print_message "payload_dumper failed on $file. Skipping..." warning
        rm -rf "${EI_BP:?}/$basename"
        continue
      fi
    else
      # Factory ZIP — extract individual partition images with 7z
      for image_name in "${PARTITIONS2EXTRACT[@]}"; do
        print_message "Extracting \"$image_name\"..." debug

        if ! 7z e "$file" -o"$EI_BP/$basename" "$image_name.img" -r &>/dev/null; then
          print_message "Failed to extract $image_name.img from $file. Skipping..." warning
          rm -f "$EI_BP/$basename/$image_name.img"
        fi
      done
    fi

    rm -f "$file"

    extraction_end=$(date +%s)
    print_message "Dump completed in $((extraction_end - extraction_start))s." debug
  done
else
  [ -d "$EAI_BP" ] && print_message "No ZIP or BIN files found in \"$EAI_BP\"." warning
fi

# ---------------------------------------------------------------------------
# Step 3: Mount / extract partition images into filesystem trees
# ---------------------------------------------------------------------------
if [ -d "$EI" ]; then
  print_message "Extracting partition images..." info

  for dir in "$EI"/*/; do
    dir="${dir%/}"
    [[ -d "$dir" ]] || continue

    print_message "Processing \"${dir##*/}\"..." info
    extraction_start=$(date +%s)

    for image_name in "${PARTITIONS2EXTRACT[@]}"; do
      if [ -f "$dir/$image_name.img" ]; then
        extract_image "$dir" "$image_name"
        rm -f "$dir/$image_name.img"
      fi
    done

    extraction_end=$(date +%s)
    print_message "Image extraction completed in $((extraction_end - extraction_start))s." debug
  done
fi

# ---------------------------------------------------------------------------
# Step 4: Build props, sysconfig, and module zip for each device
# ---------------------------------------------------------------------------
if [ -d "$EI" ]; then
  print_message "Building module props and features..." info

  for dir in "$EI"/*/; do
    dir="${dir%/}"
    [[ -d "$dir" ]] || continue

    print_message "Processing \"${dir##*/}\"..." info
    extraction_start=$(date +%s)

    print_message "Building system.prop / module.prop..." info
    ./build_props.sh "$dir"

    print_message "Building sysconfig features..." info
    ./build_sysconfig.sh "$dir"

    # Optional: significantly increases module size
    # print_message "Building bootanimation..." info
    # ./build_bootanimation.sh "$dir"

    print_message "Building Magisk/KernelSU module..." info
    ./build_module.sh "$dir"

    extraction_end=$(date +%s)
    print_message "Build completed in $((extraction_end - extraction_start))s." debug
  done
fi