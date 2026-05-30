#!/bin/bash
# utils.sh - Shared utility functions for BuildProp scripts
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

print_message() {
  local message="$1"
  local level="$2"
  local datetime
  datetime="\033[1;37m$(date +'%H:%M:%S')\033[0m"

  case "$level" in
    error)   message="[\033[1;31mERROR\033[0m]   ($datetime) $message" ;;
    warning) message="[\033[1;33mWARNING\033[0m] ($datetime) $message" ;;
    info)    message="[\033[1;32mINFO\033[0m]    ($datetime) $message" ;;
    debug)   message="[\033[1;36mDEBUG\033[0m]   ($datetime) $message" ;;
    *)       message="\033[1;37m$message\033[0m" ;;
  esac

  echo -e "$message"

  if [[ "$2" == "error" ]]; then
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Directory processing
# ---------------------------------------------------------------------------
# Process directories either directly or by enumerating through a path.
#
# Args:
#   $1  SCRIPT      - Script to execute for each directory (defaults to $0)
#   $2  TARGET_DIR  - Optional: Specific directory to process
#   $3  SEARCH_DIR  - Optional: Search root (defaults to ./extracted_images)
process_directories() {
  local script="${1:-$0}"
  if [[ -n "$2" ]]; then
    dir="$2"
  else
    local search_dir="${3:-./extracted_images}"
    for dir in "$search_dir"/*/; do
      dir="${dir%/}"
      [[ -d "$dir" ]] || continue
      print_message "Processing \"${dir##*/}\"..." debug
      "./$script" "$dir"
    done
    # Enumeration complete — exit cleanly so callers do not double-execute.
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# Package management
# ---------------------------------------------------------------------------
# Install packages by name using the system's available package manager.
install_packages() {
  local package_names=("$@")
  local package_manager=""

  if   command -v apt-get &>/dev/null; then package_manager="apt-get"
  elif command -v apt     &>/dev/null; then package_manager="apt"
  elif command -v pacman  &>/dev/null; then package_manager="pacman"
  elif command -v dnf     &>/dev/null; then package_manager="dnf"
  elif command -v yum     &>/dev/null; then package_manager="yum"
  elif command -v zypper  &>/dev/null; then package_manager="zypper"
  elif command -v pkg     &>/dev/null; then package_manager="pkg"
  else
    print_message "No supported package manager found on this system." error
    return 1
  fi

  local use_sudo=false
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
      use_sudo=true
    else
      print_message "Root privileges (sudo) are required to install packages." error
      return 1
    fi
  fi

  run_cmd() {
    if $use_sudo; then sudo "$@"; else "$@"; fi
  }

  # Refresh package index where applicable
  case "$package_manager" in
    apt-get|apt)   run_cmd "$package_manager" update -y &>/dev/null ;;
    dnf|yum)       run_cmd "$package_manager" check-update -y &>/dev/null || true ;;
    pacman)        run_cmd "$package_manager" -Sy &>/dev/null ;;
    zypper)        run_cmd "$package_manager" refresh &>/dev/null ;;
  esac

  for package in "${package_names[@]}"; do
    local already_installed=false

    case "$package_manager" in
      apt-get|apt)
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed" && already_installed=true ;;
      pacman)
        pacman -Q "$package" &>/dev/null && already_installed=true ;;
      dnf|yum)
        rpm -q "$package" &>/dev/null && already_installed=true ;;
      zypper)
        zypper -q info "$package" 2>/dev/null | grep -q "Installed.*: Yes" && already_installed=true ;;
      pkg)
        pkg info "$package" &>/dev/null && already_installed=true ;;
    esac

    if $already_installed; then
      print_message "$package is already installed." debug
      continue
    fi

    print_message "Installing $package..." info
    case "$package_manager" in
      apt-get|apt)  run_cmd "$package_manager" install -y "$package" &>/dev/null ;;
      pacman)       run_cmd "$package_manager" -S --noconfirm "$package" &>/dev/null ;;
      dnf|yum)      run_cmd "$package_manager" install -y "$package" &>/dev/null ;;
      zypper)       run_cmd "$package_manager" install -y "$package" &>/dev/null ;;
      pkg)          run_cmd "$package_manager" install -y "$package" &>/dev/null ;;
    esac
    print_message "$package installed successfully." info
  done
}

# ---------------------------------------------------------------------------
# File utilities
# ---------------------------------------------------------------------------
# Copy files matching patterns from SOURCE_DIR into DEST_DIR.
#
# Args:
#   $1  SOURCE_DIR  - Source directory
#   $2  DEST_DIR    - Destination directory
#   $3  FILES_LIST  - Space-separated glob patterns
copy_specific_files() {
  if [[ "$#" -lt 3 ]]; then
    print_message "Usage: copy_specific_files SOURCE_DIR DEST_DIR FILES_LIST" info
    return 1
  fi

  local src_dir="$1" dest_dir="$2" files_list="$3"

  if [[ ! -d "$src_dir" ]]; then
    print_message "Source directory '$src_dir' does not exist." error
    return 1
  fi

  mkdir -p "$dest_dir" || {
    print_message "Failed to create destination directory '$dest_dir'." error
    return 1
  }

  local copied=0
  for file in "$src_dir"/*; do
    [[ -f "$file" ]] || continue
    local filename="${file##*/}"
    for pattern in $files_list; do
      if echo "$filename" | grep -q "$pattern"; then
        if cp "$file" "$dest_dir/"; then
          copied=$((copied + 1))
        else
          print_message "Failed to copy: \"$filename\"" warning
        fi
        break
      fi
    done
  done

  print_message "Copied $copied file(s) to \"$dest_dir\"." debug
  return 0
}

# ---------------------------------------------------------------------------
# Property helpers
# ---------------------------------------------------------------------------
# Find build.prop / system.prop files within a directory (host-side).
find_prop_files() {
  local dir="$1"
  local prop_files=()

  while IFS= read -r -d '' file; do
    if [[ "$file" == */build.prop || "$file" == */system.prop ]]; then
      prop_files+=("$file")
    fi
  done < <(find "$dir" -type f -print0 2>/dev/null)

  echo "${prop_files[@]}"
}

# Grep a single property value from a file or inline content.
grep_prop() {
  local prop="$1"
  shift
  local source="$*"

  if [[ -f "$source" ]]; then
    grep -m1 "^${prop}=" "$source" 2>/dev/null | cut -d= -f2- | head -n1
  else
    echo "$source" | grep -m1 "^${prop}=" 2>/dev/null | cut -d= -f2- | head -n1
  fi
}

# Walk known property prefixes and return the first matching key=value pair.
get_property() {
  local prop="$1"
  shift
  local files="$*"

  local prefixes="ro ro.board ro.system ro.vendor ro.product ro.product.product
    ro.product.bootimage ro.product.vendor ro.product.odm ro.product.system
    ro.product.system_ext"

  local prefix name value
  for prefix in $prefixes; do
    name="${prefix}.${prop}"
    value=$(grep_prop "$name" "$files")
    if [[ -n "$value" ]]; then
      echo "${name}=${value}"
      return 0
    fi
  done
}

# ---------------------------------------------------------------------------
# Prop builder helpers
# ---------------------------------------------------------------------------
to_system_prop() {
  if [[ -z "$1" ]]; then
    print_message "No string provided to to_system_prop." error
    return 1
  fi
  system_prop="${system_prop}${1}
"
}

to_module_prop() {
  if [[ -z "$1" ]]; then
    print_message "No string provided to to_module_prop." error
    return 1
  fi
  module_prop="${module_prop}${1}
"
}

add_prop_as_ini() {
  local fn="$1" key="$2" val="$3"

  if [[ -z "$fn" ]] || [[ "$(type -t "$fn")" != "function" ]]; then
    print_message "Invalid function name '$fn' provided to add_prop_as_ini." error
    return 1
  fi
  if [[ -z "$key" ]]; then
    print_message "No property key provided to add_prop_as_ini." error
    return 1
  fi
  if [[ -z "$val" ]]; then
    print_message "No property value provided for '$key'." error
    return 1
  fi

  "$fn" "${key}=${val}"
}

build_system_prop() {
  local prop_name="$1"
  local prop_value
  prop_value=$(grep_prop "$prop_name" "$EXT_PROP_CONTENT")

  if [[ -z "$prop_value" ]]; then
    print_message "\"$prop_name\" not found." warning
    return 1
  fi

  add_prop_as_ini "to_system_prop" "$prop_name" "$prop_value"
}

extract_image() {
  local dest_dir="$1" image_name="$2"

  if [[ -z "$dest_dir" ]]; then
    print_message "No destination directory provided to extract_image." error
    return 1
  fi
  if [[ -z "$image_name" ]]; then
    print_message "No image name provided to extract_image." error
    return 1
  fi

  if [[ -f "$dest_dir/$image_name.img" ]]; then
    print_message "Extracting \"${dest_dir##*/}/$image_name.img\"" debug
    7z x "$dest_dir/$image_name.img" -o"$dest_dir/extracted/$image_name" -y &>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Bootstrap: source requirements
# ---------------------------------------------------------------------------
if [[ -f "requirements.sh" ]]; then
  # shellcheck source=requirements.sh
  . ./requirements.sh
else
  echo "[WARNING] requirements.sh not found — skipping dependency check." >&2
fi