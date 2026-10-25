#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$DIR/images/rootfs.img"
ESP="$DIR/images/esp.img"

fastboot "$@" getvar product 2>&1 | grep -q 'product: *nabu' || { echo "Error: Device is not nabu" >&2; exit 1; }
fastboot "$@" getvar partition-size:linux 2>&1 | grep -q "partition-size:linux:" || { echo "Error: Linux partition not found. Run partition in TWRP first." >&2; exit 1; }
fastboot "$@" getvar partition-size:esp 2>&1 | grep -q "partition-size:esp:" || { echo "Error: ESP partition not found. Run partition in TWRP first." >&2; exit 1; }

[ -f "$ROOTFS" ] || { echo "Error: $ROOTFS not found" >&2; exit 1; }
[ -f "$ESP" ] || { echo "Error: $ESP not found" >&2; exit 1; }

echo "Erasing partitions..."
fastboot "$@" erase linux || { echo "Error: Failed to erase linux" >&2; exit 1; }
fastboot "$@" erase esp || { echo "Error: Failed to erase esp" >&2; exit 1; }

echo "Flashing rootfs..."
fastboot "$@" flash linux "$ROOTFS" || { echo "Error: Failed to flash rootfs" >&2; exit 1; }
echo "Flashing ESP..."
fastboot "$@" flash esp "$ESP" || { echo "Error: Failed to flash ESP" >&2; exit 1; }

echo "Rebooting..."
fastboot "$@" reboot || { echo "Error: Failed to reboot" >&2; exit 1; }
echo "Done!"
