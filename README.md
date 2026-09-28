# mobir-air-patch

Unofficial patches for the MobIR Android app, for Guide MobIR Air thermal cameras.

> This is **not** an official project. It has no relation to Wuhan Guide Infrared Co., Ltd.
> This repository does **not** include any APK. Use an APK that you got yourself.
> For personal use only. Do not share patched APKs.

## Patches

| Dir | Target | App version | Status |
|---|---|---|---|
| [`cb360/`](cb360/) | MobIR Air body temperature model (serial number starts with `CB360`). Fixes crash and wrong temperature (-19.2 °C) | 1.4.96 | Tested on a real device |

See the `README.md` in each directory for details.

## Requirements

- Linux or WSL (bash)
- `java` (11 or newer), `patch`, `zip`, `unzip`, `curl`, `sha256sum`

## Quick start

```bash
cd cb360
bash make_cb360patch.sh /path/to/MobIR_1.4.96_APKPure.apk
```

## Credits

Made with Claude Code (Anthropic), model `claude-opus-5-5` (Claude Opus 5.5), and checked on a real device by a human.
See each patch README for tools and test devices.

## License

[MIT](LICENSE) for the files in this repository (scripts, patch lines we added, and docs).
The MobIR app and its code belong to Wuhan Guide Infrared Co., Ltd. This license does not cover them.
