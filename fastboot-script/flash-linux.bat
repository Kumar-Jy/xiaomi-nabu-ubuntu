@echo off
setlocal enabledelayedexpansion

set DIR=%~dp0
set ROOTFS=%DIR%images\rootfs.img
set ESP=%DIR%images\esp.img

fastboot %* getvar product 2>&1 | findstr /r /c:"^product: *nabu" >nul || (
  echo Error: Device is not nabu
  exit /B 1
)
fastboot %* getvar partition-size:linux 2>&1 | findstr /c:"partition-size:linux:" >nul || (
  echo Error: Linux partition not found. Run partition in TWRP first.
  exit /B 1
)
fastboot %* getvar partition-size:esp 2>&1 | findstr /c:"partition-size:esp:" >nul || (
  echo Error: ESP partition not found. Run partition in TWRP first.
  exit /B 1
)

if not exist "%ROOTFS%" (
  echo Error: %ROOTFS% not found
  exit /B 1
)
if not exist "%ESP%" (
  echo Error: %ESP% not found
  exit /B 1
)

echo Erasing partitions...
fastboot %* erase linux || (
  echo Error: Failed to erase linux
  exit /B 1
)
fastboot %* erase esp || (
  echo Error: Failed to erase esp
  exit /B 1
)

echo Flashing rootfs...
fastboot %* flash linux "%ROOTFS%" || (
  echo Error: Failed to flash rootfs
  exit /B 1
)
echo Flashing ESP...
fastboot %* flash esp "%ESP%" || (
  echo Error: Failed to flash ESP
  exit /B 1
)

echo Rebooting...
fastboot %* reboot || (
  echo Error: Failed to reboot
  exit /B 1
)
echo Done!
