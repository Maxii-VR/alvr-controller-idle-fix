# ALVR idle-hold patch — build & install instructions

**Status: BUILT AND TESTED — final candidate, awaiting in-headset confirmation.**

> **Public release is version 1.0.** The v1/v2/v3 numbering used below refers to
> internal build iterations during development; none but the final one was ever
> published, so the shipped patcher and its README carry no history of them.
> Kept here because it records *why* the code is shaped the way it is — §11 in
> particular is the reason the input release and the device-role guard exist,
> and neither should be removed without reading it.

**Target machine:** Windows 11, NVIDIA RTX 3090, Meta Quest 3 over ALVR
**ALVR version:** v20.14.1 (must match exactly)
**Install path:** `C:\Program Files\alvr_launcher_windows\installations\v20.14.1`
**Estimated time:** ~10 min setup + ~3 min compile

> **If you just want the fix, you do not need this document.** Use the
> ready-made patcher in the release zip — double-click
> `INSTALL.bat`. This document is for *rebuilding* the patch from source, which is
> only needed when ALVR releases a new version.

---

## 0. Revision history

| Date | Change |
| --- | --- |
| 2026-09-20 | First successful build + install. Corrected four errors found during the build; see §10. |
| 2026-09-20 | **v2.** Withdrew the first build: it caused stuck controller input. Root cause and fix in §11. |
| 2026-09-21 | **v3, final.** Restored the 300 s hold (safe once inputs are released), added hold-duration logging. |

---

## 1. What this fixes

In VRChat, when a controller is set down its avatar hand snaps to the default
pose (arm drops to the side), taking any hand-parented UI with it.

**Root cause (confirmed by source reading + log measurement):**

`alvr/server_openvr/cpp/alvr_server/Controller.cpp:187-205`

```cpp
bool enabled = (controllerMotion != nullptr || handSkeleton != nullptr) && ...;
pose.poseIsValid       = enabled;
pose.deviceIsConnected = enabled;   // <-- reports UNPLUGGED, not "untracked"
pose.result = enabled ? vr::TrackingResult_Running_OK : vr::TrackingResult_Uninitialized;
```

When the Quest stops supplying controller motion, ALVR tells SteamVR the
controller was **physically disconnected**. VRChat's documented response to a
disconnect is to animate the arm back to the avatar's default pose.

Measured from a 136 s `log_tracking` capture on this machine:

| Metric | Value |
| --- | --- |
| `hand_skeletons` null | 44187 / 44187 ticks (100%) |
| `/user/head` absent | 0 ticks (stream never stalled) |
| Right controller absent | 16.6% of ticks, 14 episodes, longest 7.12 s |
| Left controller absent | 4.9% of ticks, 9 episodes, longest 1.51 s |
| Tick rate during a 7.12 s dropout | mean 3.7 ms, max 13 ms (healthy) |

The patch holds the last good pose instead of reporting a disconnect.

---

## 2. Prerequisites

**Administrator is NOT required for the build.** Only the final file copy into
`Program Files` (§6) needs elevation.

1. **Git** — https://git-scm.com/download/win (skip if `git --version` works).
   Also provides `unzip.exe`, which the build needs — see §5.

2. **rustup** — https://rustup.rs (download & run `rustup-init.exe`, accept defaults).
   Plain `stable` is correct. *(This tag has no `rust-toolchain.toml`, so nothing
   is pinned; built successfully on stable 1.98.1.)*

3. **Visual Studio 2022** with the **"Desktop development with C++"** workload.
   This supplies the MSVC compiler and linker. The Build Tools edition is enough.

4. **libclang** — needed by `bindgen`. The official LLVM installer is ~860 MB;
   the 26 MB Python wheel contains the same DLL and is much faster:

   ```powershell
   python -m pip download libclang --only-binary=:all: --dest $env:TEMP\libclang-dl --no-deps
   # rename the .whl to .zip, extract, then:
   #   <extracted>\libclang-*.data\platlib\clang\native\libclang.dll
   # copy it to C:\libclang\bin\libclang.dll
   ```

   Then set `LIBCLANG_PATH=C:\libclang\bin` for the build shell.

5. Close and reopen PowerShell, then verify:
   ```powershell
   git --version ; cargo --version
   ```

> **Chocolatey is not needed.** See §10.3 — the `--ci` flag skips it entirely.
> No cmake, nasm, or yasm is needed either. ALVR downloads FFmpeg and x264 as
> prebuilt ZIPs; it never compiles them.

---

## 3. Get the source (exact version)

```powershell
cd C:\
git clone --recurse-submodules --branch v20.14.1 https://github.com/alvr-org/ALVR.git ALVR-build
cd ALVR-build
git submodule update --init --checkout --recursive
```

The `--recurse-submodules` / `submodule update` steps are **required** — the
build needs the bundled `openvr` submodule.

---

## 4. Apply the patch

The patch file is at `patch\alvr-idle-hold-v20.14.1.patch`
(full text also in Appendix A below).

```powershell
cd C:\ALVR-build
git apply --check patch\alvr-idle-hold-v20.14.1.patch
git apply         patch\alvr-idle-hold-v20.14.1.patch
git diff --stat
```

Expected output of the last command:
```
 alvr/server_openvr/cpp/alvr_server/Controller.cpp | 146 +++++++++++++++++++++-
 alvr/server_openvr/cpp/alvr_server/Controller.h   |  29 +++++
 2 files changed, 173 insertions(+), 2 deletions(-)
```

If `git apply --check` fails, STOP — the checked-out version is not v20.14.1.

> The older `alvr-idle-hold-v20.14.1.patch` and `alvr-idle-hold.patch` in this
> folder are superseded. They used `Debug()` for the hold log line, which is
> compiled out of release builds — see §10.1.

---

## 5. Build

```powershell
cd C:\ALVR-build
$env:PATH = "$env:USERPROFILE\.cargo\bin;C:\Program Files\Git\usr\bin;$env:PATH"
$env:LIBCLANG_PATH = "C:\libclang\bin"

cargo xtask prepare-deps --platform windows --ci
cargo xtask build-streamer --release --gpl
```

Note the two additions to the original instructions:

* **`C:\Program Files\Git\usr\bin` on PATH.** `prepare-deps` shells out to
  `unzip`, which is not a Windows built-in. Git for Windows ships it. Without
  this the dependency step panics at `dependencies.rs:35`.
* **`--ci` on `prepare-deps`.** This sets `skip_admin_priv` and skips the
  `choco install` step. See §10.3.

**`prepare-deps` will fail on the FFmpeg download — this is expected.** See
§10.2 for the fix; you must place FFmpeg manually. x264 downloads fine.

**The `--gpl` flag is required.** The installed official build bundles FFmpeg
7.1 (`avcodec-61.dll` is present in `bin\win64`), which means it was built with
`--gpl`. Our replacement DLL must match or it will fail to load.
`--gpl` only adds `--features gpl` to cargo; FFmpeg itself is a prebuilt download.

**Build output:**
```
C:\ALVR-build\build\alvr_streamer_windows\bin\win64\driver_alvr_server.dll
```

Clean build took **3m 13s**. It should compile with **zero warnings from the
patch** — the only warnings are pre-existing `f32`/`f64` ones in `alvr_dashboard`.

---

## 6. Install (back up first — not optional)

1. **Fully close SteamVR and the ALVR Dashboard.** Confirm no `vrserver.exe`,
   `vrmonitor.exe`, or `ALVR Dashboard.exe` in Task Manager.

2. **Back up the whole installation folder:**
   ```powershell
   Copy-Item -Recurse "C:\Program Files\alvr_launcher_windows\installations\v20.14.1" `
                      "C:\alvr-backup"
   ```
   Verify the copy before trusting it:
   ```powershell
   $a = Get-ChildItem "C:\Program Files\alvr_launcher_windows\installations\v20.14.1" -Recurse -File | Measure-Object Length -Sum
   $b = Get-ChildItem "C:\alvr-backup" -Recurse -File | Measure-Object Length -Sum
   "$($a.Count)/$($a.Sum)  vs  $($b.Count)/$($b.Sum)"   # must match; was 22 files / 280533936 bytes
   ```

3. **Copy in the patched driver only** (leave every other file alone).
   This step **requires Administrator** — it writes to `Program Files`:
   ```powershell
   Copy-Item "C:\ALVR-build\build\alvr_streamer_windows\bin\win64\driver_alvr_server.dll" `
             "C:\Program Files\alvr_launcher_windows\installations\v20.14.1\bin\win64\driver_alvr_server.dll" -Force
   ```

4. Confirm the copy landed:
   ```powershell
   Get-FileHash "C:\Program Files\alvr_launcher_windows\installations\v20.14.1\bin\win64\driver_alvr_server.dll" -Algorithm SHA256
   ```

5. Start the ALVR Dashboard, start streaming, launch SteamVR.

### Known-good hashes (SHA256, v20.14.1)

| File | Hash | Size |
| --- | --- | --- |
| Stock `driver_alvr_server.dll` | `5B2DC0012254FA3C45268ED655C3F589B2D460A62907C620670CFB5D22A48FA8` | 14,497,792 |
| Patched `driver_alvr_server.dll` (**v3, current**) | `28514EA68F12C825C1D756F67707E2D00F68CC9CCA2A4B0008F2DF7E6D11EC60` | 14,607,872 |
| Patched `driver_alvr_server.dll` (v2, superseded) | `001444D2C5F2B9085BE3E91A4218E66FE110D7DED5F0B321523FF12D1A6554DE` | 14,607,872 |
| Patched `driver_alvr_server.dll` (v1, **withdrawn**) | `0DC254863DE800AA37FFDD9614850FDEE6164360B1089DB517BFF601DF6E425E` | 14,606,848 |

---

## 7. Verify it worked

**Functional test:** in VRChat, set a controller on a table and wait 10-15 s.
The avatar hand should stay exactly where the controller is, instead of the
arm dropping to the side. ✅ *Confirmed working 2026-09-20.*

**Log test (definitive):**

1. ALVR Dashboard -> Settings -> Extra -> Logging -> enable `log_to_disk`.
   (`log_tracking` is **not** needed for this check and writes ~17 MB / 2 min.)
2. **Restart SteamVR** — `log_to_disk` is only read when the driver loads
   (`server_openvr/src/lib.rs:444`, it has no `real-time` flag).
3. Reproduce the drop, then stop streaming.
4. Open `C:\Program Files\alvr_launcher_windows\installations\v20.14.1\session_log.txt`
   Each freeze produces a pair of lines:
   ```
   controller left: source inactive, holding last pose
   controller left: source recovered after 412 ms, hold released
   ```
   The first marks a freeze starting; the second reports how long it lasted.
   A freeze that runs the full timeout instead gives:
   ```
   controller left: hold timed out after 300000 ms, releasing device (if this repeats, check the controller battery)
   ```
   Holds that start and then recover, with the hand NOT dropping in game, mean
   the fix is working. Repeated timeouts mean the controller is genuinely going
   away — check its battery before suspecting the patch.
5. **Turn `log_to_disk` back off** when you are done.

> This line is emitted with `Warn()`, not `Debug()`. That is deliberate and
> **required** — see §10.1. Expect roughly one line per idle episode (~23 in a
> 136 s session). If you find the log noise annoying once you have confirmed the
> fix, change `Warn(` back to `Debug(` in `Controller.cpp` and rebuild; you will
> lose the log test but the fix itself is unaffected.

**Regression test (do this before trusting a new build).** This is the v1 bug
from §11 and it is the one that actually matters:

1. In VRChat, push and HOLD the thumbstick forward so you are walking.
2. Keep holding it and set the controller down, or otherwise let tracking drop.
3. You must stop moving within a second or so. If you keep walking, the input
   release in §11.1 is not working -- stop and do not ship the build.
4. Press some buttons during the freeze. They should do nothing (the device is
   held, not live), and must respond again the moment tracking returns.

Also watch for `hold ended, releasing device` in the log: it marks the timeout
expiring and the device going back to a normal disconnect.

**Binary sanity check** (confirms you are actually running the patched DLL):

```powershell
$p = "C:\Program Files\alvr_launcher_windows\installations\v20.14.1\bin\win64\driver_alvr_server.dll"
$t = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p))
if ($t.Contains("source inactive, holding last pose")) { "PATCHED" } else { "STOCK" }
```

---

## 8. Rollback

Requires Administrator.

```powershell
Copy-Item -Recurse -Force "C:\alvr-backup\*" `
          "C:\Program Files\alvr_launcher_windows\installations\v20.14.1\"
```

Or run `UNINSTALL.bat` from the patcher folder, or simply reinstall v20.14.1
from the ALVR Launcher.

---

## 9. Known risks and caveats

* ~~**This patch has never been compiled.**~~ **Resolved.** It compiles clean
  and is confirmed working in VRChat.
* **Unsigned self-built driver.** This is why the backup in §6 matters. SteamVR
  does not verify driver signatures, so it loads without complaint.
* **Long disconnects are usually a flat battery, not this patch.** If a
  controller drops out for tens of seconds and needs a Meta-button press to come
  back, check its charge before suspecting the driver. A controller running out
  of charge powers itself off, wakes briefly on a button press, then drops
  again — easy to miss with battery notifications turned off. A `hold timed out`
  line in the log (rather than `source recovered`) is the tell.
* **ALVR updates overwrite it.** Any launcher update replaces
  `driver_alvr_server.dll`. Re-run §3-6 against the new version tag.
  The patch may need rebasing if `Controller.cpp` changes upstream.
  **Expect the FFmpeg URL in §10.2 to have rotted further by then.**
* **300-second hold timeout.** A controller genuinely powered off disconnects
  after 5 minutes (`IDLE_HOLD_TIMEOUT_NS` in `Controller.h`). This is only safe
  because `ReleaseAllInputs()` clears input on the way into a hold — v1 paired a
  300 s hold with live stale input and that let a thumbstick keep driving the
  player (§11.1). **Never raise or restore this timeout without that release in
  place.**
* **Behaviour change:** hands freeze in place rather than disappearing. This is
  intentional and matches VRChat's older behaviour.
* **Inputs are released on a dropout** (§11.1). If tracking drops for a moment
  while you are gripping an object, you will let go of it. Deliberate: the
  alternative is an input stuck live with no way to cancel it.
* **Stale PDB.** `alvr_server_openvr.pdb` in the install folder still belongs to
  the stock DLL, so a crash dump would symbolise incorrectly. Copy the matching
  PDB from the build output alongside the DLL if you ever need to debug a crash.
* **Timestamp arithmetic is unsigned.** If `targetTimestampNs` ever moves
  backwards, `targetTimestampNs - m_lastEnabledTimestampNs` wraps to a huge
  value, the hold condition goes false, and behaviour falls back to stock. This
  fails safe, so it is left as-is.

---

## 10. Corrections to the original instructions

Four things in the first draft of this document were wrong. All were found
during the first real build. They are fixed inline above; recorded here so the
same time is not lost next version.

### 10.1 `Debug()` is compiled out of release builds — the log test could never work

`alvr/server_openvr/build.rs` defines the logging macro only in debug builds:

```rust
#[cfg(debug_assertions)]
build.define("ALVR_DEBUG_LOG", None);
```

and `Logger.cpp:53` makes `Debug()` a no-op without it:

```cpp
void Debug(const char* format, ...) {
#ifdef ALVR_DEBUG_LOG
    ...
#else
    (void)format;      // <-- release build: does nothing at all
#endif
}
```

Since we build with `--release`, the original patch's `Debug("controller %s:
source inactive, holding last pose", ...)` produced **no output whatsoever**.
§7's "definitive log test" would have shown nothing, leaving no way to tell a
working patch from a broken one.

**Fix:** the line now uses `Warn()`, which is always compiled and routes to both
`session_log.txt` and the SteamVR driver log (`Logger.cpp:36`). `Info()` is not
a substitute — it deliberately does not write to disk.

### 10.2 The hardcoded FFmpeg download URL is dead

`dependencies.rs:60-73` fetches a fixed filename from BtbN's *rolling* `latest`
release:

```
https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n7.1-latest-win64-gpl-shared-7.1.zip
```

That release now carries only 8.1, 9.0 and master. The 7.1 asset is gone.
`curl` follows the redirect, receives a **9-byte "Not Found" body**, saves it as
`temp_download.zip`, and `unzip` then fails with "End-of-central-directory
signature not found" — a confusing error that has nothing to do with your setup.

**Fix — place FFmpeg manually after `prepare-deps` fails:**

```powershell
$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-07-31-14-10/ffmpeg-n7.1.5-12-g1fdbca85aa-win64-gpl-shared-7.1.zip"
Invoke-WebRequest $url -OutFile "$env:TEMP\ffmpeg71.zip" -UseBasicParsing
Expand-Archive "$env:TEMP\ffmpeg71.zip" -DestinationPath "C:\ALVR-build\deps\windows" -Force
Rename-Item "C:\ALVR-build\deps\windows\ffmpeg-n7.1.5-12-g1fdbca85aa-win64-gpl-shared-7.1" "ffmpeg"
```

**You must stay on 7.1.x.** The soname suffixes are what matter:
`avcodec-61`, `avutil-59`, `avfilter-10`, `swscale-8`. These match the FFmpeg
DLLs ALVR already ships in `bin\win64`, which is what makes it safe to copy
*only* the driver DLL. FFmpeg 8.1 would produce `avcodec-62` and the driver
would fail to load against the installed runtime.

If `autobuild-2026-07-31-14-10` is also gone, list the dated tags and pick any
`n7.1.x` `win64-gpl-shared` asset:

```powershell
$r = Invoke-RestMethod "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases?per_page=40" -Headers @{'User-Agent'='ps'}
foreach ($rel in $r) { $rel.assets | Where-Object name -match '^ffmpeg-n7\.1.*win64-gpl-shared.*\.zip$' | ForEach-Object { "$($rel.tag_name) -> $($_.name)" } }
```

### 10.3 Chocolatey, cmake, vulkan-sdk and pkg-config were never needed

`prepare_windows_deps()` runs `choco install zip unzip llvm vulkan-sdk
pkgconfiglite` — but only when `skip_admin_priv` is false, and **`--ci` sets it
true** (`main.rs:183`, `dependencies.rs:77-90`). With `--ci`, `prepare-deps`
does nothing but download the two ZIPs.

Of that package list, only `llvm` is genuinely required, and only for its
`libclang.dll` (bindgen). Checking `alvr/server_openvr/Cargo.toml` and
`build.rs`:

* `pkg-config` is a **`[target.'cfg(target_os = "linux")'.build-dependencies]`** entry — Linux only.
* `vulkan` is probed only inside `#[cfg(target_os = "linux")]` — Linux only.
* `zip`/`unzip` — only `unzip` is used, and Git for Windows already provides it.

So the whole "run PowerShell as Administrator for this section" instruction was
unnecessary. Only §6 step 3 needs elevation.

### 10.4 There is no `rust-toolchain.toml` in this tag

The original document said the repo pins Rust 1.97.1 and warned against
hand-picking a toolchain. No such file exists at `v20.14.1`; nothing is pinned.
The build succeeded on **stable 1.98.1**.

---

## 11. Why the input release and role guard exist (development history)

v1 fixed the arm drop and was confirmed working in VRChat. It also shipped a
real bug: while a hold was active, controller input stayed frozen at its last
value. If the thumbstick happened to be pushed forward when tracking dropped,
the player kept walking, and no button press would respond, for as long as the
hold lasted -- up to 300 s.

The root mistake was asserting `deviceIsConnected = true` without understanding
everything that flag means to the rest of ALVR. It has two consequences, §11.1
and §11.2.

> **A note on how this was diagnosed, because the record matters.**
> The bug was reported alongside 30-60 s episodes where a controller went
> unresponsive mid-use. Those episodes were initially attributed to §11.2, and
> this document said so. They were later traced to a **discharged controller
> battery** (the controller powered off; the Meta button woke it briefly). §11.1
> is provable from the code and was real regardless. §11.2 is a genuine
> violation of an upstream contract and worth fixing on its own merits -- but it
> was **not** shown to be the cause of those episodes, and this document should
> not have claimed it was. Treat §11.2 as "v1 broke a documented invariant",
> not as "v1 caused the outage".

### 11.1 Stale input stays live once you claim the device is connected

Poses and inputs travel on **completely separate paths**. `OnPoseUpdate` is
driven by tracking samples; `SetButton` (`alvr_server.cpp:502`) is driven by
client input events. v1 only touched the pose path.

When a controller's source goes idle the client stops sending button and axis
events too, so SteamVR keeps serving the last value it was given. Upstream gets
away with this because the same tick reports `deviceIsConnected = false`, and
games discard input from a disconnected device. v1 reported the device as
connected and tracking OK, so VRChat had every reason to act on a thumbstick it
believed was genuinely held forward.

Note `Controller::SetButton` early-returns when `last_pose.poseIsValid` is
false. That is upstream's own guard, and holding a valid pose disables it.

**Fix:** `ReleaseAllInputs()` neutralises every registered component on the way
into a hold -- booleans to false, scalars to 0.0, which is neutral for both
one-sided (trigger, grip) and two-sided (thumbstick axis) components. Because
`m_buttonHandles` does not record component types, v2 also tracks
`m_buttonIsBinary` at registration time so each component can be reset
correctly.

### 11.2 `deviceIsConnected` is ALVR's device-arbitration flag

From `server_openvr/src/lib.rs`, upstream's own comment above `SetTracking`:

> There are two pairs of controllers/hand tracking devices registered in
> OpenVR, two lefts and two rights. If enabled with use_separate_hand_trackers,
> we select at runtime which device to use... **Selection is done by setting
> deviceIsConnected.**

Both twins are handed identical `FfiHandData` every tick (`alvr_server.cpp:401-421`),
and each works out whether it owns the hand:

```cpp
bool enabledAsHandTracker = handData.isHandTracker && (device_id == HAND_TRACKER_LEFT_ID || ...);
bool enabledAsController  = !handData.isHandTracker && (device_id == HAND_LEFT_ID || ...);
```

The loser **must** report `deviceIsConnected = false`. v1 pinned the deselected
twin at connected with a frozen pose for up to 300 s, so two devices claimed the
same hand at once. `SetButton` pushes input to both twins unconditionally
(`alvr_server.cpp:503-510`), so there was no clean device to bind to.

This machine has `use_separate_hand_trackers = true` in `session.json`, so both
twins are live, and v1 genuinely did leave a deselected twin claiming a hand.
What is *not* established is that this produced the reported 30-60 s episodes --
see the note at the top of §11. Fix it because the invariant is real, not
because of that symptom.

**Fix:** split the old `enabled` into two distinct questions, and only hold when
this device still owns its hand:

```cpp
bool roleActive = enabledAsHandTracker || enabledAsController;  // do I own this hand?
bool haveSample = (controllerMotion != nullptr || handSkeleton != nullptr);
bool enabled = haveSample && roleActive;
```

Hold only when `roleActive && !haveSample`. If the twin owns the hand, fall
straight through to the stock disabled path and report disconnected, preserving
arbitration.

### 11.3 The timeout, and why v3 puts it back

v2 cut the hold from 300 s to 10 s. That was the right call *at the time*: with
input still live, the timeout was the only bound on how long a stuck thumbstick
could drive the player, so it had to be short.

Once §11.1 is fixed the reasoning inverts. A hold no longer carries stale input,
so the only thing a long timeout costs is that a genuinely powered-off
controller lingers as a frozen hand for a few minutes. Meanwhile a *short*
timeout actively defeats the patch: any dropout longer than the cap hands the
arm-drop straight back, which is the bug we set out to fix.

So **v3 restores 300 s**. The dependency runs one way only, and it is worth
being explicit about it:

> A long hold is safe **only** while `ReleaseAllInputs()` runs on entry.
> If that release is ever removed or bypassed, the timeout must come back down
> with it.

### 11.4 Deliberate trade-off

Releasing inputs on a dropout means a momentary tracking loss while gripping an
object will drop it. That is clearly preferable to an uncancellable stuck input.

### 11.5 What this says about the upstream report

§1's diagnosis still holds -- conflating "no sample this tick" with "device
unplugged" is the real defect. But it also shows why the *minimal* upstream fix
is not simply forcing `deviceIsConnected = true`: that flag is load-bearing for
device arbitration. Any upstream change has to keep the twin-selection contract
intact, which is worth stating explicitly in the issue.

---

## Appendix A — full patch

The authoritative copy is `alvr-idle-hold-v20.14.1-FINAL.patch` in this folder,
and the same file ships inside the patcher under `source/`. It is the v2 build:
`Warn(` rather than `Debug(` (§10.1), role-aware holding and input release
(§11), and a 10 s timeout.

Apply it to a clean `v20.14.1` checkout; `git apply --check` should be silent
and `git diff --stat` should report 146 insertions across the two files.

Key shape of the logic:

```cpp
if (enabled) {
    m_lastEnabledTimestampNs = targetTimestampNs;
    m_holdingLastPose = false;
    m_inputsReleased = false;
} else {
    if (!m_inputsReleased) {          // never leave input stuck live
        ReleaseAllInputs();
        m_inputsReleased = true;
    }

    bool canHold = roleActive        // never fight the twin for the hand
        && this->last_pose.poseIsValid && this->last_pose.deviceIsConnected
        && m_lastEnabledTimestampNs != 0
        && targetTimestampNs > m_lastEnabledTimestampNs
        && (targetTimestampNs - m_lastEnabledTimestampNs) < IDLE_HOLD_TIMEOUT_NS;

    if (canHold) {
        // re-publish last_pose, connected, velocities zeroed
        return false;
    }
    // else: fall through to the stock path -> deviceIsConnected = false
}
```

---

## Appendix B — verified build environment

| Component | Version / location |
| --- | --- |
| OS | Windows 11 Pro 10.0.26200 |
| Rust | stable 1.98.1 (x86_64-pc-windows-msvc) |
| MSVC | Visual Studio 2022 Community, VC.Tools.x86.x64 |
| libclang | 18.1.1 (PyPI wheel) at `C:\libclang\bin` |
| unzip | `C:\Program Files\Git\usr\bin\unzip.exe` (Git 2.55.0) |
| x264 | 0.164.r3086 msvc16 |
| FFmpeg | n7.1.5-12-g1fdbca85aa win64-gpl-shared |
| Source | `C:\ALVR-build` @ tag `v20.14.1` |
| Build time | 3m 13s clean, 7s incremental |

**Driver imports** — the patched DLL's dependency set is byte-for-byte identical
to the stock one, which is what confirms it is a safe drop-in:

```
avcodec-61.dll, avutil-59.dll, swscale-8.dll, openvr_api.dll,
msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll   (+ Windows system DLLs)
```
