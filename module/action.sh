#!/system/bin/busybox sh
# action.sh - Interactive action script for PlayIntegrityFix and TrickyStore configuration
# Runs via Magisk/KernelSU action button.

MODPATH="${0%/*}"

# Resolve MODPATH robustly
[ -z "$MODPATH" ] || ! echo "$MODPATH" | grep -q '/data/adb/modules/' &&
  MODPATH="$(dirname "$(readlink -f "$0")")"

# Source module utilities
[ -f "$MODPATH/utils.sh" ] && . "$MODPATH/utils.sh" || abort "! utils.sh not found!"

# ---------------------------------------------------------------------------
# Load property content (once)
# ---------------------------------------------------------------------------
MODPROP_FILES=$(find_prop_files "$MODPATH/" 1)
SYSPROP_FILES=$(find_prop_files "/" 2)
MODPROP_CONTENT=$(echo "$MODPROP_FILES" | xargs cat)
SYSPROP_CONTENT=$(echo "$SYSPROP_FILES" | xargs cat)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Emit a compact JSON object from a whitespace-separated list of variable names.
build_json() {
  echo '{'
  for PROP in $1; do
    printf '  "%s": "%s",\n' "$PROP" "$(eval "echo \$$PROP")"
  done | sed '$s/,//'
  echo '}'
}

# Force-stop and clear data for core Google apps.
handle_google_apps() {
  GOOGLE_APPS="com.google.android.gsf com.google.android.gms com.google.android.googlequicksearchbox"

  for google_app in $GOOGLE_APPS; do
    su -c am force-stop "$google_app"
    am broadcast -a android.settings.ACTION_BLUETOOTH_PRIVATE_DATA_GRANTED \
      --es package "$google_app" --ei value 0
    am broadcast -a android.settings.ACTION_BLUETOOTH_PRIVATE_DATA_GRANTED \
      --es package "$google_app" --ei value 1
    su -c pm clear "$google_app"
    ui_print " * Cleared $google_app"
  done
}

# ---------------------------------------------------------------------------
# PlayIntegrityFix — generate pif.json
# ---------------------------------------------------------------------------
PlayIntegrityFix() {
  local PIF_MODULE_DIR="/data/adb/modules/playintegrityfix"
  local PIF_DIR="$PIF_MODULE_DIR/pif.json"

  # Validate PIF installation
  if [ -z "$PIF_MODULE_DIR" ] || [ ! -s "$PIF_MODULE_DIR/module.prop" ]; then
    abort "PlayIntegrityFix module is missing or inaccessible. Skipping." false
    return
  elif grep -q "Fork" "$PIF_MODULE_DIR/module.prop"; then
    abort "Detected a Fork version of PlayIntegrityFix. Please install the official version." false
    return
  fi

  ui_print " - Detected official PlayIntegrityFix. Building pif.json..."

  local PIF_LIST="MODEL MANUFACTURER FINGERPRINT SECURITY_PATCH DEVICE_INITIAL_SDK_INT"

  # Resolve module properties
  MODEL=$(grep_prop "ro.product.model"              "$MODPROP_CONTENT")
  MANUFACTURER=$(grep_prop "ro.product.manufacturer" "$MODPROP_CONTENT")
  PRODUCT=$(grep_prop "ro.product.product.name"     "$MODPROP_CONTENT")
  FINGERPRINT=$(grep_prop "ro.product.build.fingerprint" "$MODPROP_CONTENT")
  SECURITY_PATCH=$(grep_prop "ro.vendor.build.security_patch" "$MODPROP_CONTENT")
  DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.first_api_level" "$SYSPROP_CONTENT")
  [ -z "$DEVICE_INITIAL_SDK_INT" ] && \
    DEVICE_INITIAL_SDK_INT=$(grep_prop "ro.product.build.version.sdk" "$SYSPROP_CONTENT")

  local CWD_PIF="$MODPATH/pif.json"
  local update_count=0

  # Remove stale local copy
  [ -f "$CWD_PIF" ] && rm -f "$CWD_PIF"

  case "$PRODUCT" in
    *beta*)
      ui_print "  - Building pif.json from current BETA module properties..."
      build_json "$PIF_LIST" >"$CWD_PIF"
      ;;
    *)
      ui_print "  - Non-BETA module detected."
      ui_print "  - Download pif.json from GitHub? (chiteroman/PlayIntegrityFix)"

      volume_key_event_setval "DOWNLOAD_PIF_GITHUB" true false "ACTION_DOWNLOAD_PIF_GITHUB"

      if boolval "$ACTION_DOWNLOAD_PIF_GITHUB"; then
        download_file \
          "https://raw.githubusercontent.com/chiteroman/PlayIntegrityFix/main/module/pif.json" \
          "$CWD_PIF"
      else
        ui_print " - Crawling latest Google Pixel Beta OTA releases..."

        download_file "https://developer.android.com/topic/generic-system-image/releases" DL_GSI_HTML

        RELEASE_DATE="$(date -D '%B %e, %Y' -d \
          "$(grep -m1 -o 'Date:.*' DL_GSI_HTML | cut -d\  -f2-4)" '+%Y-%m-%d' | head -n1)"

        RELEASE_IDS="$(awk '/\(Beta\)/ {flag=1} /Build:/ && flag {print; flag=0}' DL_GSI_HTML \
          | sed -n 's/.*Build: \([A-Z0-9.]*\).*/\1/p')"

        ui_print "  - Latest Available Beta Releases ($RELEASE_DATE)"

        RELEASE_LIST=""
        for ID in $RELEASE_IDS; do
          RELEASE_VERSION=$(awk -v id="$ID" '$0 ~ id {flag=1} /Android [0-9]+/ && flag {print; flag=0}' \
            DL_GSI_HTML | sed -n 's/.*Android \([0-9]*\).*/\1/p' | head -n1)
          INCREMENTAL=$(grep -o "$ID-[0-9]*-" DL_GSI_HTML | sed "s/$ID-//;s/-//" | head -n1)
          RELEASE_INFO="A${RELEASE_VERSION}-${ID}-${INCREMENTAL}"
          [ -z "$RELEASE_LIST" ] && RELEASE_LIST="$RELEASE_INFO" \
            || RELEASE_LIST="$RELEASE_LIST $RELEASE_INFO"
          ui_print "   - Android $RELEASE_VERSION ($ID) [$INCREMENTAL]"
        done

        volume_key_event_setoption "RELEASE" "$RELEASE_LIST" "SELECTED_RELEASE"

        SELECTED_RELEASE_ID=$(echo "$SELECTED_RELEASE" | cut -d- -f2)
        SELECTED_RELEASE_VERSION=$(echo "$SELECTED_RELEASE" | cut -d- -f1 | tr -d 'A')
        SELECTED_RELEASE_INCREMENTAL=$(echo "$SELECTED_RELEASE" | cut -d- -f3)

        download_file \
          "https://developer.android.com/about/versions/$SELECTED_RELEASE_VERSION/download-ota" \
          DL_OTA_HTML

        DEVICE_LIST="$(grep -A1 'tr id=' DL_OTA_HTML | awk -F '[<>"]' '
          /tr id=/ { id = $3 }
          /<td>/   { devices = devices ? devices sprintf(",%s (%s)", $3, id) : sprintf("%s (%s)", $3, id) }
          END      { print devices }')"

        CODENAME_LIST="$(grep -A1 'tr id=' DL_OTA_HTML | awk -F '[<>"]' '
          /tr id=/ { codenames = codenames ? codenames "," $3 : $3 }
          END      { print codenames }')"

        ui_print "  - Devices Available:"
        echo "$DEVICE_LIST" | tr ',' '\n' | while read -r device; do
          ui_print "   - $device"
        done

        volume_key_event_setoption "CODENAME" "$(echo "$CODENAME_LIST" | tr ',' ' ')" "SELECTED_CODENAME"

        SELECTED_MODEL=$(echo "$DEVICE_LIST" | tr ',' '\n' \
          | awk -F'[(,]' -v c="$SELECTED_CODENAME" '$0~c{print $1}')

        SECURITY_PATCH_DATE="${RELEASE_DATE%-*}-05"
        SELECTED_RELEASE_VERSION_OR_CODENAME=$(
          [ "$SELECTED_RELEASE_VERSION" -gt 15 ] && echo "Baklava" \
            || echo "$SELECTED_RELEASE_VERSION"
        )

        MODEL="$SELECTED_MODEL"
        MANUFACTURER="Google"
        FINGERPRINT="google/${SELECTED_CODENAME}_beta/$SELECTED_CODENAME:\
${SELECTED_RELEASE_VERSION_OR_CODENAME}/${SELECTED_RELEASE_ID}/${SELECTED_RELEASE_INCREMENTAL}:\
user/release-keys"
        SECURITY_PATCH="$SECURITY_PATCH_DATE"

        build_json "$PIF_LIST" >"$CWD_PIF"
        rm -f DL_*_HTML
      fi
      ;;
  esac

  # Sync generated pif.json to PIF module directory
  if [ ! -s "$CWD_PIF" ]; then
    ui_print "  ! Generated PIF file is empty or missing."
  elif [ ! -s "$PIF_DIR" ]; then
    update_count=$((update_count + 1))
    cp "$CWD_PIF" "$PIF_DIR"
    ui_print "  ++ pif.json created at \"$PIF_DIR\"."
  elif ! cmp -s "$CWD_PIF" "$PIF_DIR"; then
    update_count=$((update_count + 1))
    mv "$PIF_DIR" "${PIF_DIR}.old" 2>/dev/null
    cp "$CWD_PIF" "$PIF_DIR"
    ui_print "  ++ pif.json updated at \"$PIF_DIR\"."
  else
    ui_print "  - pif.json unchanged."
  fi

  if [ "$update_count" -gt 0 ]; then
    ui_print "***************************************"
    ui_print "  ! Disconnect from your Google account: https://myaccount.google.com/device-activity"
    ui_print "  ! Clear data for Google GMS, GSF, and Google apps."
    ui_print "  ! Reboot and sign back in — verify device shows as \"$MODEL\"."
    ui_print "  ! More info: https://t.me/PixelProps/157"
    ui_print "***************************************"
  fi
}

# ---------------------------------------------------------------------------
# TrickyStore — generate target.txt
# ---------------------------------------------------------------------------
TrickyStoreTarget() {
  [ -d "/data/adb/tricky_store" ] || return

  ui_print " - Building TrickyStore target.txt..."

  local TARGET_DIR="/data/adb/tricky_store/target.txt"
  local CWD_TARGET="$MODPATH/target.txt"

  [ -f "$CWD_TARGET" ] && rm -f "$CWD_TARGET"

  PACKAGES=$(pm list packages | sed 's/package://g')
  SPECIAL_PACKAGES="com.google.android.gms com.google.android.gsf com.android.vending"

  if grep -qE "^teeBroken=(true|1)$" /data/adb/tricky_store/tee_status 2>/dev/null; then
    ui_print "  ! Hardware Attestation unavailable (teeBroken=true) — all packages flagged."
    PACKAGES=$(echo "$PACKAGES" | sed 's/$/!/')
  else
    for pkg in $SPECIAL_PACKAGES; do
      PACKAGES=$(echo "$PACKAGES" | sed "s/^${pkg}$/${pkg}!/")
    done
  fi

  echo "$PACKAGES" >"$CWD_TARGET"

  if [ ! -s "$CWD_TARGET" ]; then
    ui_print "  ! target.txt is empty or missing."
  elif [ ! -s "$TARGET_DIR" ]; then
    cp "$CWD_TARGET" "$TARGET_DIR"
    ui_print "  ++ target.txt created at \"$TARGET_DIR\"."
  elif ! cmp -s "$CWD_TARGET" "$TARGET_DIR"; then
    mv "$TARGET_DIR" "${TARGET_DIR}.old" 2>/dev/null
    cp "$CWD_TARGET" "$TARGET_DIR"
    ui_print "  ++ target.txt updated at \"$TARGET_DIR\"."
  else
    ui_print "  - target.txt unchanged."
  fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
ui_print "- Configuring PlayIntegrityFix & TrickyStore..."

PlayIntegrityFix
TrickyStoreTarget

sleep 5
exit 0