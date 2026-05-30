# Pixel Props — BETA

> Magisk / KernelSU / APatch module that spoofs your device's build properties to a Google Pixel,
> enabling Strong Play Integrity attestation and Pixel-exclusive features.

[![Build](https://github.com/AzeoLXC/BuildProp-BETA/actions/workflows/build.yml/badge.svg)](https://github.com/AzeoLXC/BuildProp-BETA/actions/workflows/build.yml)

---

## Features

- Spoof `build.prop` properties across all partitions (product, vendor, system, ODM, …)
- Automatic PlayIntegrityFix (`pif.json`) generation or download
- Automatic TrickyStore (`target.txt`) generation with TEE-broken detection
- SHA-256 integrity verification of all module scripts at install time
- Supports **Magisk**, **KernelSU**, and **APatch**

---

## Repository Structure

```
.
├── utils.sh                  # Shared utility functions (logging, pkg mgmt, prop helpers)
├── requirements.sh           # Dependency checker / installer
├── download_ota.sh           # Download latest OTA / factory images from Google
├── extract_images.sh         # Extract partition images and orchestrate full build pipeline
├── build_props.sh            # Build system.prop + module.prop from extracted images
├── build_sysconfig.sh        # Copy Pixel sysconfig XML features into module tree
├── build_bootanimation.sh    # (Optional) Copy bootanimation into module tree
├── build_module.sh           # Assemble and zip the final Magisk/KernelSU module
└── module/                   # Module template files (installed on device)
    ├── utils.sh              # On-device property helpers
    ├── action.sh             # Interactive action: PIF + TrickyStore config
    ├── customize.sh          # Magisk install script
    ├── service.sh            # Post-boot service hook
    ├── post-fs-data.sh       # Early-boot hook
    ├── gms_doze.sh           # GMS doze optimisation
    ├── uninstall.sh          # Clean uninstall hook
    ├── config.prop           # User-configurable module settings
    └── META-INF/             # Magisk installer metadata
```

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `bash` ≥ 5 | Script runtime |
| `aria2` | Multi-connection OTA downloads |
| `p7zip-full` | ZIP / image extraction |
| `zip` | Module packaging |
| `python3` + `pip` | payload_dumper dependency |
| `payload_dumper` | Android OTA payload extraction |

Run `bash utils.sh` once to auto-install all dependencies (requires `sudo`).

---

## Usage

### 1 — Download OTA

```bash
# Stable release
bash download_ota.sh husky shiba

# Beta release
bash download_ota.sh husky_beta16 shiba_beta16

# QPR beta
bash download_ota.sh husky_beta16qpr1
```

### 2 — Full pipeline (extract → build props → package)

```bash
bash extract_images.sh
```

The built `.zip` modules are written to `./result/`.

### 3 — Individual build steps

```bash
# Build props only for a specific extracted directory
bash build_props.sh ./extracted_images/husky_AB12

# Build the module zip only
bash build_module.sh ./extracted_images/husky_AB12
```

---

## GitHub Actions

The workflow at `.github/workflows/build.yml` supports:

- **Manual trigger** (`workflow_dispatch`) — provide a comma-separated device list:
  ```
  husky,shiba,husky_beta16
  ```
- **Scheduled trigger** — runs every Monday at 00:00 UTC against a default device set.

On success the workflow creates a GitHub Release containing the module `.zip` files.

---

## Module Installation

1. Download the `.zip` for your device from [Releases](https://github.com/AzeoLXC/BuildProp-BETA/releases).
2. Flash via **Magisk** / **KernelSU** / **APatch**.
3. Reboot.
4. Tap the module **Action** button to configure PlayIntegrityFix and TrickyStore.
5. Verify with [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck).

---

## Configuration (`module/config.prop`)

```properties
# Set to false to disable sensitive prop checks (useful if no hardware volume keys)
pixelprops.sensitive.props=true
pixelprops.sensitive.pihooks=true
```

---

## Support

- Telegram channel: [t.me/PixelProps](https://t.me/PixelProps)
- Script author: [@T3SL4](https://t.me/T3SL4)

---

## License

See [LICENSE](LICENSE).