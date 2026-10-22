# Changelog

All notable changes to **Ubuntu Linux for Xiaomi Pad 5 (nabu)** are documented here.

---

## [Build 2026-10-22] - All-in-One Installer & Kernel Fixes

### 🚀 Installer & Flashing
- **All-in-One Flashable Installer:** Converted rootfs build into a unified installer zip package:
  - **Recovery Flashing:** Flash directly in TWRP or OrangeFox recovery via **Install Zip**.
  - **Fastboot Flashing:** Supports one-click desktop flashing from PC using `flash-linux.bat` (Windows) or `flash-linux.sh` (Linux/macOS).
- **Integrated DBKP UEFI Patching:** Automatically patches the Android `boot` partition with DualBootKernelPatcher and `SM8150_EFI.fd` payload so UEFI and rEFInd boot directly without extra sideload steps.
- **Embedded ESP Image (`images/esp.img`):** FAT32 `ESPNABU` partition preloaded with rEFInd bootloader, GopRotate driver, AndroidBootPkg, and pre-compiled Ubuntu UKIs.
- **Windows Dual-Boot Support:** Includes WinPE recovery image (`pe.img`) and `install.bat` / `sta.exe` helpers for seamless triple-boot (Android + Windows + Ubuntu).
- **Filesystem Optimization:** Rootfs image is automatically minimized using `resize2fs -M`, significantly speeding up download, flashing, and extraction times.

### ⚙️ Kernel & RootFS Fixes
- **Hardware Video Acceleration Out-of-the-Box:**
  - Added `/etc/modprobe.d/qcom-iris.conf` (`options qcom_iris allow_fw_boot=1`) to automatically unlock Qualcomm Iris HW decoding (`H.264`, `HEVC`, `VP9`) and encoding without manual intervention.
- **Sensors, Auto-Rotation & Auto-Brightness Out-of-the-Box:**
  - Integrated `hexagonrpcd` service, `libssc`, and patched `iio-sensor-proxy` with Snapdragon Sensor Core (SSC) support.
  - Added `/etc/dracut.conf.d/nabu-dsp.conf` to bundle Hexagon SLPI DSP firmware in early initramfs, preventing DSP probe errors on boot.
  - Added `/etc/udev/rules.d/80-iio-sensor-proxy.rules` with `ssc-accel` tag for immediate D-Bus detection by Mutter and KWin.
  - Enabled `qrtr-ns.service`, `hexagonrpcd.service`, `nabu-tablet-mode.service`, and `nabu-autobrightness.service`.
- **Camera Support:**
  - Pre-installed `libcamera-tools`, `gstreamer1.0-libcamera`, and `v4l-utils` for seamless front (8MP `ov8856`) and rear (13MP `ov13b10`) camera operation.
- **Fixed `kdump-tools` / `initramfs-tools` Crash:**
  - Added APT preferences pinning (`no-kdump.pref`) with `Pin-Priority: -1` to permanently prevent `kdump-tools`, `makedumpfile`, and `crash` from being pulled in by `ubuntu-desktop`.
  - Added automated post-install purge to eliminate conflicting maintainer scripts.
- **Fixed Missing `/dev/root` Bug:**
  - Added persistent UDEV rule (`61-dev-root.rules`) mapping `PARTNAME="linux"` to `/dev/root`. Resolves failures in `initramfs-tools`, `mkinitramfs`, and userspace disk utilities on mainline boots.
- **Automatic UKI Generator Hook (`zz-update-uki`):**
  - Added system kernel hook (`/etc/kernel/postinst.d/zz-update-uki`).
  - Installing ANY kernel package (upstream kernels via `dpkg -i *.deb` or updates via `apt upgrade`) automatically builds the Unified Kernel Image with `ukify` (kernel + initrd + DTB + cmdline) and copies it to ESP (`EFI/Ubuntu/`).
  - Added matching cleanup hook (`/etc/kernel/postrm.d/zz-remove-uki`) to clean up old EFI binaries when kernels are removed.
- **Comprehensive Troubleshooting Guide:**
  - Created [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) detailing tested solutions for existing users regarding kernel upgrades, UKI creation, sensors, cameras, audio, and hardware video decoding.

---

## [Ubuntu 26.04 Resolute Raccoon Baseline]

### 🖥️ Desktop & System Features
- **Ubuntu 26.04 LTS (Resolute Raccoon)** ARM64 base with standard Ubuntu GNOME desktop.
- **Wayland Hardware Acceleration:** Mesa Turnip (Vulkan) + Freedreno (OpenGL) for Adreno 640 GPU.
- **Audio Support:** Full quad-speaker and headphone support via Cirrus Logic CS35L41 and ALSA UCM (`xiaomi-nabu-alsa`).
- **Modem & Sensors:** SLPI, sensor mapping, and peripheral services (`rmtfs`, `tqftpserv`, `pd-mapper`).
- **Display & Rotation:** 120Hz display configuration with `monitors.xml` and console font scaling.
- **ZRAM Swapping:** Pre-configured 10 GiB compressed zram swap for multitasking responsiveness.
- **Dual Kernel Support:** Ships with both `xiaomi-nabu-linux-6.14` and `xiaomi-nabu-linux-6.17` (with UFS slowdown patch).
