# 🛠️ Xiaomi Pad 5 (nabu) Ubuntu Troubleshooting Guide

This guide provides tested, step-by-step solutions for hardware, kernel, and driver issues on the Xiaomi Pad 5 running Ubuntu.

---

## Table of Contents
1. [Kernel Upgrade & Installation Errors (`kdump-tools` / `/dev/root`)](#1-kernel-upgrade--installation-errors-kdump-tools--devroot)
2. [Unified Kernel Image (UKI) & Bootloader Issues](#2-unified-kernel-image-uki--bootloader-issues)
3. [Sensors, Auto-Rotation & Auto-Brightness](#3-sensors-auto-rotation--auto-brightness)
4. [Hardware Video Acceleration (Qualcomm Iris HW Decoder/Encoder)](#4-hardware-video-acceleration-qualcomm-iris-hw-decoderencoder)
5. [Camera Setup & Testing (`libcamera`)](#5-camera-setup--testing-libcamera)
6. [Audio & Quad Speakers (Cirrus CS35L41)](#6-audio--quad-speakers-cirrus-cs35l41)
7. [Wi-Fi Permanent MAC Address (`nabu-pmac`)](#7-wi-fi-permanent-mac-address-nabu-pmac)
8. [Sleep / Suspend Sensor Recovery](#8-sleep--suspend-sensor-recovery)

---

## 1. Kernel Upgrade & Installation Errors (`kdump-tools` / `/dev/root`)

### Symptom
When installing a new kernel `.deb` or running `sudo apt upgrade`, `dpkg` crashes with:
```
mkinitramfs: failed to determine device for /
update-initramfs: failed for /var/lib/kdump/initrd.img-... with 1.
run-parts: /etc/kernel/postinst.d/kdump-tools exited with return code 1
dpkg: error processing package linux-image-... (--configure):
 subprocess installed post-installation script returned error exit status 1
```

### Cause
Ubuntu installs `kdump-tools` by default. Its initramfs generator relies on `/dev/root` being present. On mainline ARM64 bootloaders, the root filesystem is mounted directly via partition UUID or label (`root=PARTLABEL=linux`), so `/dev/root` does not exist and `kdump-tools` crashes.

### Fix
1. **Purge `kdump-tools` and complete the pending installation:**
   ```bash
   sudo apt purge -y kdump-tools makedumpfile kexec-tools crash
   sudo dpkg --configure -a
   ```

2. **Prevent `kdump-tools` from ever being reinstalled:**
   ```bash
   sudo tee /etc/apt/preferences.d/no-kdump.pref << 'EOF'
   Package: kdump-tools
   Pin: release *
   Pin-Priority: -1
   EOF
   ```

3. **Add `/dev/root` udev rule as a permanent safety net:**
   ```bash
   sudo tee /etc/udev/rules.d/61-dev-root.rules << 'EOF'
   # Create /dev/root symlink from the active root mount source
   SUBSYSTEM=="block", PROGRAM="/usr/bin/findmnt -no SOURCE /", RESULT=="%N", SYMLINK+="root"
   EOF
   sudo udevadm control --reload && sudo udevadm trigger
   ```

---

## 2. Unified Kernel Image (UKI) & Bootloader Issues

### Symptom
After installing a kernel update, the device reboots into the old kernel or rEFInd cannot find the new `.efi` boot file.

### How UKI Works on Nabu
The bootloader boots a single Unified Kernel Image (`.efi`) containing:
`Linux Kernel (vmlinuz)` + `Initramfs (initrd)` + `Device Tree (dtb)` + `Cmdline`

### Manual UKI Generation
If the kernel post-install script didn't generate your UKI automatically, generate it manually:

```bash
# 1. Identify kernel version
KVER=$(uname -r)   # or specify the newly installed version, e.g. 7.3.0-0

# 2. Mount the ESP partition (usually /dev/sda31 or /dev/disk/by-partlabel/esp)
sudo mkdir -p /mnt/esp
sudo mount /dev/disk/by-partlabel/esp /mnt/esp 2>/dev/null || sudo mount /dev/sda31 /mnt/esp

# 3. Build the UKI directly into rEFInd's Ubuntu directory
sudo ukify build \
  --linux="/boot/vmlinuz-$KVER" \
  --initrd="/boot/initrd.img-$KVER" \
  --devicetree="/boot/dtb-$KVER" \
  --cmdline="root=PARTLABEL=linux rw fw_devlink=permissive" \
  --uname="$KVER" \
  --output="/mnt/esp/EFI/Ubuntu/${KVER}.efi"

# 4. Sync and unmount
sudo sync && sudo umount /mnt/esp
```

---

## 3. Sensors, Auto-Rotation & Auto-Brightness

### Symptom
- Auto-rotation does not work in GNOME or KDE.
- Auto-brightness does not respond to ambient lighting.
- `dmesg` reports repeated crashes:
  ```
  qcom_q6v5_pas 2400000.remoteproc: fatal error received: err_qdi.c:964:EF:sensor_process:0x1:TMR_CLNT_1:0x80:dog_virtual_user.c:240:USER-PD DOG detects stalled initialization
  remoteproc remoteproc0: crash detected in slpi: type fatal error
  ```

### Cause
Sensors on SM8150 run on the Hexagon SLPI DSP (Sensor Low Power Island). On boot, the SLPI firmware queries its JSON sensor registry over FastRPC (`/dev/fastrpc-sdsp`). If [`hexagonrpcd`](file:///usr/bin/hexagonrpcd) is not running to serve [`/lib/firmware/hexagonfs/sensors/`](file:///lib/firmware/hexagonfs/sensors/), SLPI times out and crashes.

### Fix
1. **Configure the `nabu-pkgs` repository (if not already added):**
   ```bash
   sudo tee /etc/apt/sources.list.d/nabu.sources << 'EOF'
   Types: deb
   URIs: https://github.com/Kumar-Jy/nabu-pkgs/releases/download/ubuntu/
   Suites: ./
   Trusted: yes
   EOF
   sudo apt update
   ```

2. **Install Hexagon DSP sensor tools & patched `iio-sensor-proxy`:**
   ```bash
   sudo apt install -y hexagonrpcd libssc iio-sensor-proxy qrtr-tools
   ```

3. **Ensure `ssc-accel` is present in udev rules:**
   ```bash
   sudo sed -i 's/ssc-light/ssc-accel ssc-light/g' /usr/lib/udev/rules.d/80-iio-sensor-proxy.rules 2>/dev/null || true
   sudo udevadm control --reload
   sudo udevadm trigger --subsystem-match=misc
   ```

4. **Enable the services:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now qrtr-ns.service
   sudo systemctl enable --now hexagonrpcd.service hexagonrpcd-suspend.service hexagonrpcd-resume.service
   sudo systemctl restart iio-sensor-proxy.service
   ```

5. **Verify live sensor streams:**
   ```bash
   # Test Accelerometer
   ssccli --sensor accelerometer --timeout 2

   # Test Ambient Light Sensor
   ssccli --sensor light --timeout 2

   # Test Compass / Magnetometer
   ssccli --sensor compass --timeout 2
   ```

6. **Verify D-Bus exposure for GNOME/KDE:**
   ```bash
   busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy HasAccelerometer
   # Output should be: b true
   ```

---

## 4. Hardware Video Acceleration (Qualcomm Iris HW Decoder/Encoder)

### Symptom
- Opening `/dev/video0` or `/dev/video1` returns `Permission denied` (`[Errno 13]`), even as root.
- Video playback in Firefox/Chrome/MPV pegs the CPU at 100%.

### Cause
The upstream `qcom-iris` kernel driver includes a security parameter `allow_fw_boot` which defaults to `N` (disabled).

### Fix
1. **Enable Iris firmware boot in modprobe:**
   ```bash
   echo "options qcom_iris allow_fw_boot=1" | sudo tee /etc/modprobe.d/qcom-iris.conf
   ```

2. **Apply immediately without rebooting:**
   ```bash
   echo 1 | sudo tee /sys/module/qcom_iris/parameters/allow_fw_boot
   ```

3. **Verify decoder capabilities:**
   ```bash
   v4l2-ctl -d /dev/video0 --list-formats-out
   ```
   Output:
   - `H264` (H.264)
   - `HEVC` (H.265)
   - `VP90` (VP9)

---

## 5. Camera Setup & Testing (`libcamera`)

### Hardware Specs
- **Rear Camera**: 13 MP OmniVision `ov13b10` with `cn3927` auto-focus actuator.
- **Front Camera**: 8 MP OmniVision `ov8856`.

### Note on Camera Architecture
Nabu cameras use the **Qualcomm CAMSS** subsystem and V4L2 subdevices. They do **not** work through simple standard webcam capture tools; they require **`libcamera`** with the `simple` pipeline handler.

### Testing Camera Capture
1. **Install tools:**
   ```bash
   sudo apt install -y libcamera-tools gstreamer1.0-libcamera
   ```

2. **List detected cameras:**
   ```bash
   cam --list
   ```
   You should see:
   - `1: Internal front camera (/base/soc@0/cci@ac4a000/i2c-bus@1/camera@10)`
   - `2: Internal back camera (/base/soc@0/cci@ac4a000/i2c-bus@0/camera@10)`

3. **Capture a test photo:**
   ```bash
   # Capture 1 frame from front camera
   cam -c 1 -C1 -F front_test_#.ppm

   # Capture 1 frame from back camera
   cam -c 2 -C1 -F back_test_#.ppm
   ```

---

## 6. Audio & Quad Speakers (Cirrus CS35L41)

### Symptom
No sound from the 4 speakers or internal microphone.

### Fix
1. **Install Nabu ALSA UCM2 configurations:**
   ```bash
   sudo apt install -y xiaomi-nabu-alsa alsa-ucm-conf
   ```

2. **Restart audio server:**
   ```bash
   systemctl --user restart pipewire wireplumber
   ```

3. **Verify speakers:**
   ```bash
   speaker-test -c 2 -t wav
   ```

---

## 7. Wi-Fi Permanent MAC Address (`nabu-pmac`)

### Symptom
Wi-Fi MAC address changes randomly on every reboot, resulting in duplicate entries on routers and saved networks disconnecting.

### Fix
Install `nabu-pmac`, which derives a permanent, deterministic MAC address from the Snapdragon SoC serial number:
```bash
sudo apt install -y nabu-pmac
sudo systemctl enable --now nabu-pmac.service
```

---

## 8. Sleep / Suspend Sensor Recovery

### Symptom
After waking the tablet from suspend (`s2idle`), screen auto-rotation stops updating.

### Fix
`nabu-tablet-mode` includes sleep/wake handlers (`nabu-sensors-recover` and `nabu-sensors-resume.sh`) that safely re-synchronize the FastRPC listener and notify Mutter/KWin:
```bash
sudo apt install -y nabu-tablet-mode
sudo systemctl enable --now nabu-tablet-mode.service
```
Manual recovery toggle command:
```bash
nabu-tablet-toggle
```

---

## Quick Reference Summary

| Feature | Service / Package | Configuration File | Verification Command |
| :--- | :--- | :--- | :--- |
| **Sensors** | `hexagonrpcd` + `libssc` | `/lib/firmware/hexagonfs/` | `ssccli --sensor accelerometer` |
| **Auto-Rotation** | `iio-sensor-proxy` | `/etc/udev/rules.d/80-iio-sensor-proxy.rules` | `busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy HasAccelerometer` |
| **Video HW Decode** | `qcom-iris` | `/etc/modprobe.d/qcom-iris.conf` | `v4l2-ctl -d /dev/video0 --all` |
| **Cameras** | `libcamera-tools` | Device tree CAMSS | `cam --list` |
| **Audio** | `xiaomi-nabu-alsa` | `/usr/share/alsa/ucm2/` | `alsamixer` |
| **Wi-Fi MAC** | `nabu-pmac` | Systemd service | `ip link show wlan0` |
