# Licensing notice

This repository contains a patch against [ALVR](https://github.com/alvr-org/ALVR),
plus scripts to install a build of it. Two different licences apply, because the
source and the released binary are not the same thing.

## The source in this repository — MIT

`patch/`, `patcher/` and `docs/` are a modification of ALVR, which is MIT
licensed. They are offered under the same terms; see [LICENSE](LICENSE).

## The released binary — GPL

The `driver_alvr_server.dll` attached to each GitHub Release is built with ALVR's
`--gpl` option. That links **FFmpeg** (with `--enable-gpl`) and **x264**, both of
which are GPL-2.0-or-later. The resulting binary is a combined work and is
therefore distributed under the **GPL-2.0-or-later**.

`--gpl` is not optional here. Official ALVR v20.14.1 ships FFmpeg 7.1 in
`bin\win64` (`avcodec-61.dll`, `avutil-59.dll`, `avfilter-10.dll`, `swscale-8.dll`),
so a replacement driver must link against the same libraries to load at all.

### Corresponding source

Everything needed to reproduce the released binary:

| Component | Where |
| --- | --- |
| ALVR | <https://github.com/alvr-org/ALVR> at tag `v20.14.1` |
| The modification | [`patch/alvr-idle-hold-v20.14.1.patch`](patch/) in this repository |
| Build instructions | [`docs/BUILDING.md`](docs/BUILDING.md) |
| FFmpeg | `ffmpeg-n7.1.5-12-g1fdbca85aa-win64-gpl-shared-7.1` from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds), release `autobuild-2026-07-31-14-10` |
| x264 | `libx264_0.164.r3086_msvc16` from [ShiftMediaProject/x264](https://github.com/ShiftMediaProject/x264) |

Build with:

```powershell
cargo xtask build-streamer --release --gpl
```

FFmpeg is at <https://ffmpeg.org/> and x264 at <https://www.videolan.org/developers/x264.html>;
neither is modified here, and both are used as prebuilt binaries downloaded by
ALVR's own build tooling.

## Trademarks and affiliation

Not affiliated with, endorsed by, or supported by the ALVR project, Meta, Valve,
or VRChat. All trademarks belong to their respective owners.
