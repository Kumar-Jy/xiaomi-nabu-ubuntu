#!/usr/bin/env bash
set -e

# Script arguments are forwarded to every fastboot call; helpers below cannot use
# "$@" (that is their own argument list), so keep a copy.
FB_ARGS=("$@")

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve images directory
if [ -d "$DIR/images" ]; then
    IMAGES_DIR="$DIR/images"
elif [ -f "$DIR/rootfs.img" ]; then
    IMAGES_DIR="$DIR"
else
    echo "Error: images directory not found at $DIR/images" >&2
    exit 1
fi

ROOTFS="$IMAGES_DIR/rootfs.img"
ESP="$IMAGES_DIR/esp.img"
UEFI="$IMAGES_DIR/alohauefi.img"

[ -f "$ROOTFS" ] || { echo "Error: rootfs image not found at $ROOTFS" >&2; exit 1; }
[ -f "$ESP" ] || { echo "Error: esp image not found at $ESP" >&2; exit 1; }

echo "==> Checking connected device..."
fastboot "$@" getvar product 2>&1 | grep -q 'product: *nabu' || { echo "Error: Device mismatch (expected nabu)"; exit 1; }

# Determine partition layout: dual/multi-boot (linux/esp) vs single-boot (userdata/cust)
# fastboot reports partition sizes as hexadecimal (e.g. "0x1D2000000"), so match
# the 0x form instead of a leading [1-9]. Getting this wrong silently selects the
# single-boot layout and overwrites userdata/cust on a dual-boot device.
has_part() {
    fastboot "${FB_ARGS[@]}" getvar "partition-size:$1" 2>&1 \
        | grep -qE "partition-size:$1:[[:space:]]*(0x[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]*|[1-9][0-9]*)"
}

if has_part linux && has_part esp; then
    echo "==> Detected dual/multi-boot partition layout (linux + esp)"
    ROOT_PART="linux"
    ESP_PART="esp"
else
    echo "==> Using single-boot partition layout (userdata + cust)"
    ROOT_PART="userdata"
    ESP_PART="cust"
fi

# Abort early if the images cannot fit, rather than flashing a truncated image.
check_fits() {
    local part="$1" img="$2" hex part_bytes img_bytes
    hex=$(fastboot "${FB_ARGS[@]}" getvar "partition-size:$part" 2>&1 \
        | sed -n "s/.*partition-size:$part:[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p" | head -n1)
    [ -n "$hex" ] || return 0
    part_bytes=$((16#$hex))
    img_bytes=$(wc -c < "$img" | tr -d '[:space:]')
    if [ "$img_bytes" -gt "$part_bytes" ]; then
        echo "Error: $(basename "$img") is $img_bytes bytes but $part is only $part_bytes bytes" >&2
        exit 1
    fi
}

check_fits "$ROOT_PART" "$ROOTFS"
check_fits "$ESP_PART" "$ESP"

echo "WARNING: this will overwrite the '$ROOT_PART' and '$ESP_PART' partitions."
echo "         Any existing data on them (including EFI/Microsoft on the ESP) is lost."
if [ -t 0 ]; then
    read -r -p "Type 'yes' to continue: " CONFIRM
    [ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }
else
    echo "==> Non-interactive run, continuing."
fi

# 1. Flash Aloha UEFI to boot partition (both slots)
if [ -f "$UEFI" ]; then
    echo "==> Flashing Aloha UEFI ($UEFI) to boot_ab..."
    fastboot "$@" flash boot_ab "$UEFI" || {
        echo "fastboot flash boot_ab failed, attempting per-slot flash..."
        fastboot "$@" flash boot_a "$UEFI" || { echo "Error flashing boot_a"; exit 1; }
        fastboot "$@" flash boot_b "$UEFI" || { echo "Error flashing boot_b"; exit 1; }
    }
else
    echo "Note: alohauefi.img not found in images/, skipping boot partition flash."
fi

# 2. Flash rootfs and ESP (fastboot flash writes the whole image; a separate
#    erase only widens the window for a half-flashed, unbootable device)
echo "==> Flashing rootfs ($ROOTFS) to $ROOT_PART..."
fastboot "$@" flash "$ROOT_PART" "$ROOTFS" || { echo "Error flashing rootfs to $ROOT_PART"; exit 1; }

echo "==> Flashing ESP ($ESP) to $ESP_PART..."
fastboot "$@" flash "$ESP_PART" "$ESP" || { echo "Error flashing ESP to $ESP_PART"; exit 1; }

# 3. Reboot
echo "==> Flashing completed successfully! Rebooting..."
fastboot "$@" reboot || { echo "Error rebooting device"; exit 1; }
