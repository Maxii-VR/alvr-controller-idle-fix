# ALVR Idle-Hold Patch

**Stops your VRChat avatar's arm from dropping when you put a controller down.**

A one-file patch for [ALVR](https://github.com/alvr-org/ALVR) v20.14.1 on Windows.
Your hand stays exactly where you left the controller instead of snapping back to
the avatar's default pose.

---

## Does this sound familiar?

You're in VRChat over ALVR on a Quest. You set a controller down on your desk for
a moment, and a few seconds later:

- Your **avatar's arm drops to its side**, back to the default pose
- Anything **parented to that hand goes with it** — a wrist menu, a held prop, a
  hand-attached UI, a pen
- Other people see your **hand fall limp** while you're mid-conversation
- **Picking the controller back up fixes it** instantly
- It happens **even though the controller is right there**, fully charged, and the
  headset is tracking fine
- Switching avatars doesn't help, and nothing in VRChat's settings changes it

If you've been searching for *VRChat hand drops when controller is idle*, *avatar
arm returns to default pose ALVR*, *controller disconnects when I set it down*, or
*wrist menu disappears when I stop holding my controller* — this is that problem.

It isn't your avatar, it isn't VRChat, and it isn't a tracking fault. It's the
ALVR driver telling SteamVR your controller was **unplugged**.

## What actually causes it

When your Touch controller stops moving, its firmware goes quiet and the Quest
stops sending motion samples for it. ALVR's OpenVR driver treats "no sample this
tick" as "device not present" and publishes a pose with
`deviceIsConnected = false`.

To SteamVR and to VRChat, that is indistinguishable from you physically
disconnecting the controller. VRChat's response to a controller disconnect is to
animate the arm back to the avatar's default pose — which is exactly what you see.

This patch changes what the driver reports: while the controller is merely idle,
it stays **connected but stationary**, holding its last known pose, so nothing
downstream thinks it vanished.

Measured on a Quest 3 over a 136-second capture, controllers were reported absent
for **16.6%** of ticks on the right hand and **4.9%** on the left, with the longest
single gap lasting **7.1 seconds** — all while the video stream never stalled once.

## Download

Grab the latest zip from the [**Releases**](../../releases/latest) page, unpack it
anywhere, and double-click `INSTALL.bat`.

## Requirements

| | |
|---|---|
| ALVR | **v20.14.1 exactly** — the installer refuses anything else |
| OS | Windows 10 / 11 |
| Also needed | SteamVR, and Administrator for the install step only |

Tested on Windows 11 + RTX 3090 + Quest 3 with Touch Plus controllers. It should
work with any headset ALVR supports, since the change is entirely server-side.

## Install

1. **Fully close** SteamVR, the ALVR Dashboard, and VRChat
2. Double-click **`INSTALL.bat`** and approve the Windows prompt
3. Start ALVR and SteamVR as usual

It replaces exactly one file — `bin\win64\driver_alvr_server.dll` inside your ALVR
installation — after backing up the original beside it. No registry keys, no
services, no startup entries, nothing else touched.

**To undo:** double-click `UNINSTALL.bat`.
**To check what's installed:** `CHECK-STATUS.bat` (read-only, no Administrator).

## Verify it worked

In VRChat, set a controller on a table and wait 10–15 seconds. The hand should
stay exactly where you left it.

## Is this safe to run?

**Be skeptical — it's an unsigned DLL from a stranger on the internet.** Here's
what you can check before trusting it.

The release binary is:

```
driver_alvr_server.dll
SHA256  28514EA68F12C825C1D756F67707E2D00F68CC9CCA2A4B0008F2DF7E6D11EC60
Size    14,607,872 bytes
```

```powershell
Get-FileHash .\driver_alvr_server.dll -Algorithm SHA256
```

The installer checks this itself and refuses to run if it doesn't match. It also
verifies your existing driver is the genuine ALVR v20.14.1 build before touching
anything, so it can't be installed onto the wrong version.

The entire source change is [one patch file](patch/) — 173 added lines across two
files. If you'd rather not run someone else's binary, **[build it yourself](docs/BUILDING.md)**;
the guide covers the whole process and takes about fifteen minutes.

Expect a SmartScreen or antivirus warning. Any self-built, unsigned driver gets
one.

> This is unofficial and not affiliated with the ALVR project. **Do not report
> ALVR bugs while it's installed** — uninstall first and confirm the problem is
> still there.

## How it works

In `Controller::OnPoseUpdate`, upstream drives three separate OpenVR fields from a
single "did a sample arrive" boolean:

```cpp
pose.poseIsValid       = enabled;
pose.deviceIsConnected = enabled;   // <-- says UNPLUGGED, not "untracked"
pose.result = enabled ? vr::TrackingResult_Running_OK : vr::TrackingResult_Uninitialized;
```

Those answer different questions. `deviceIsConnected` means *is the device
present*; `poseIsValid` means *is this pose usable*. Collapsing them turns a
momentary tracking gap into a disconnect.

The patch re-publishes the last good pose with the device still connected and
velocities zeroed, for up to 5 minutes, after which a genuinely powered-off
controller does disconnect normally.

Two details make it safe, and both matter:

**Inputs are released on entry.** During a dropout the headset stops sending
button and stick updates, so SteamVR keeps serving whatever arrived last. That's
normal and unpatched ALVR does it too — harmless there only because the device
reports disconnected, so games discard its input. Since this patch says the
opposite, it clears them itself. Otherwise a thumbstick held forward when tracking
dropped would keep walking you with no way to stop.

**A device that doesn't own its hand is never held.** ALVR registers two devices
per hand — a controller and a hand tracker — and picks between them at runtime
using `deviceIsConnected` as the selector. Holding a deselected device connected
would leave two devices claiming the same hand.

## Known limitations

- **v20.14.1 only.** Any ALVR update replaces the driver and removes the patch;
  rebuild it against the new tag.
- **Unsigned.** See above.
- **A grip blip drops what you're holding.** If tracking flickers while you're
  gripping something, the input release means you let go. That beats an input stuck
  live with no way to cancel it.
- **Hands freeze rather than vanish.** Intentional — that's the whole point.

## Troubleshooting

**A controller keeps dropping out for tens of seconds and needs a Meta button
press to come back.** Check its battery. A controller running out of charge powers
itself off, wakes briefly on a button press, then drops again — easy to miss with
battery notifications turned off. This is not the patch.

**ALVR won't start after installing.** Run `UNINSTALL.bat`.

**"Could not find ALVR automatically."** Pass the path yourself:

```powershell
.\Patch-ALVR.ps1 -InstallPath "C:\Program Files\alvr_launcher_windows\installations\v20.14.1"
```

**Want to see what it's doing?** Enable `log_to_disk` in the ALVR Dashboard
(Settings → Extra → Logging) and restart SteamVR. Every freeze is recorded in
`session_log.txt`:

```
controller left: source inactive, holding last pose
controller left: source recovered after 412 ms, hold released
controller left: hold timed out after 300000 ms, releasing device
```

A `hold timed out` line means the controller really did go away — that's the
battery case above. Turn logging back off afterwards; it writes a lot.

Fuller detail is in [`patcher/README.txt`](patcher/README.txt), which is the readme included in the download (its `source\` reference points inside the zip, not this repo).

## Building from source

See [**docs/BUILDING.md**](docs/BUILDING.md). It documents the whole process
including several things the upstream build breaks on at this tag — a dead FFmpeg
download URL, a missing `unzip`, and an unnecessary Chocolatey/Administrator step.

```powershell
git clone --recurse-submodules --branch v20.14.1 https://github.com/alvr-org/ALVR.git
cd ALVR
git apply path\to\alvr-idle-hold-v20.14.1.patch
cargo xtask build-streamer --release --gpl
```

## License and credits

All credit for ALVR goes to the [alvr-org](https://github.com/alvr-org/ALVR)
project and its contributors. This repository is a small modification of their
work and is not affiliated with or endorsed by them.

The patch and scripts here are MIT, matching ALVR. The **released binary** links
GPL-licensed FFmpeg and x264 and is therefore distributed under the GPL — see
[NOTICE.md](NOTICE.md) for the full explanation and the corresponding source offer.

Provided as-is, with no warranty of any kind.
