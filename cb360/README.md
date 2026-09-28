# MobIR Air CB360 patch

A patch for the MobIR Android app (v1.4.96).
With this patch, the **MobIR Air body temperature model (serial number starts with `CB360`)** can show the correct temperature.

> This is **not** an official project. It has no relation to Wuhan Guide Infrared Co., Ltd.
> This repository does **not** include the APK. Use an APK that you got yourself.
> For personal use only. Do not share the patched APK.

## Problem

With a MobIR Air whose serial number starts with `CB360`:

| App version | What happens |
|---|---|
| 1.4.53 and older | Image is OK, but the temperature is always about -19.2 °C |
| 1.4.79 and newer | App crashes (`NullPointerException` in `McuGuideInterface.ReadPackageData`) |

The camera is not broken.
The app treats every "MobIR Air" as the industrial model (ZX01A) and asks for the industrial calibration data.
But a CB360 camera only has body temperature calibration data (`mPackageHumanBody`), so the industrial data (`mPackageLow`) is `null`.

## What the patch does

It adds this at the top of `McuGuideInterface.ReadPackageData`:

```java
if (this.mPackageLow == null && this.mPackageHumanBody != null) {
    Log.i(TAG, "CB360 patch: mPackageLow null, use mPackageHumanBody");
    enumITARange = EnumITARange.ITA_HUMAN_BODY;
}
```

So the app uses the body temperature data when the industrial data is missing.
The change is in `cb360_ReadPackageData.patch` (smali, unified diff).

## Files

| File | Description |
|---|---|
| `make_cb360patch.sh` | Build script |
| `cb360_ReadPackageData.patch` | The patch for the smali code |
| `tools/` | apktool and uber-apk-signer (downloaded on first run) |

## Requirements

- Linux or WSL (bash)
- `java` (11 or newer), `patch`, `zip`, `unzip`, `curl`, `sha256sum`

On Ubuntu / Debian:

```bash
sudo apt install openjdk-17-jre-headless patch zip unzip curl
```

- Input APK: **MobIR 1.4.96** (`MobIR_1.4.96_APKPure.apk`)
  - SHA-256: `498540e38490333a4e24429153fa7896dbafded284cf9eaf641ccf3288b3a1d6`
  - The script stops if the SHA-256 is different. Use `--force` to try another file.

## Build

```bash
bash make_cb360patch.sh MobIR_1.4.96_APKPure.apk
```

Output: `MobIR_1.4.96_cb360patch.apk` (in the same folder as the input APK)

Options:

| Option | Description |
|---|---|
| `[output.apk]` | 2nd argument. Output file path |
| `--keep-work` | Keep the work dir in `work/<date-time>/` (default: delete it) |
| `--work-dir DIR` | Use `DIR` as the work dir (it is kept) |
| `--force` | Continue even if the input SHA-256 does not match |
| `-h`, `--help` | Show help |

Steps in the script:

1. Download apktool 3.0.3 and uber-apk-signer 1.3.0 to `tools/` (check SHA-256)
2. Check the input APK SHA-256
3. `apktool d -r` (decode to smali)
4. `patch -p1` (apply `cb360_ReadPackageData.patch`)
5. `apktool b` (rebuild)
6. Copy the original APK, remove the old signature, and replace only `classes2.dex`
7. zipalign and sign with a debug key (uber-apk-signer)
8. Check that the patch is in the output APK

## Install

The patched APK has a different signature, so you must **uninstall the current MobIR app first**.
Your app data (photos and videos in the app) will be deleted. Save them before you uninstall.

With adb:

```bash
adb uninstall com.parts.mobileir.mobileirparts
adb install MobIR_1.4.96_cb360patch.apk
```

Or copy the APK to the phone and open it with a file manager.

## Check

Plug in the camera and start the app. Then check:

- The app does not crash
- The temperature looks right (ice water: about 0 °C, skin: about 33-36 °C)

To see the log:

```bash
adb logcat | grep "CB360 patch"
```

## Notes

- Tested on: arrows Alpha (Android 16) with MobIR Air (SN `CB360...`). Temperature and photos work.
- The body temperature model probably measures about 0-60 °C. High temperatures may not be correct.
- The patched app does not get updates from Google Play.
- Version 1.5.x has a Google Play license check. This patch does not support 1.5.x.

## Credits

Analysis, patch, script, and this README were made with an AI assistant.
A human checked the result on a real device.

| Item | Used |
|---|---|
| AI assistant | Claude Code (Anthropic), model `claude-opus-5-5` (Claude Opus 5.5) |
| Decompiler (analysis only) | [jadx](https://github.com/skylot/jadx) 1.5.6 |
| Smali decode / build | [Apktool](https://github.com/iBotPeaches/Apktool) 3.0.3 |
| zipalign / sign | [uber-apk-signer](https://github.com/patrickfav/uber-apk-signer) 1.3.0 |
| Build environment | WSL2 (Linux 6.18), OpenJDK 11.0.26, GNU patch 2.7.6, Zip 3.0 |
| Test phone | FCNT arrows Alpha (M08), Android 16 |
| Test camera | Guide MobIR Air, USB Type-C, SN `CB360...` (USB VID/PID `0525:a4a0`) |
| Input app | MobIR 1.4.96 (`com.parts.mobileir.mobileirparts`, from APKPure) |

## Troubleshooting

| Message | What to do |
|---|---|
| `input SHA-256 does not match` | Use MobIR 1.4.96. Or use `--force` (the patch may fail) |
| `patch does not apply` | The APK is a different version. Use 1.4.96 |
| `zip I/O error: Permission denied` | Check that you can write to the work dir |
| Other errors | Run again with `--keep-work` and check the logs in the work dir (`apktool_d.log`, `apktool_b.log`, `signer.log`) |
