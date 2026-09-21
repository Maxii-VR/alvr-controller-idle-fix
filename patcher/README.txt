===========================================================================
  ALVR IDLE-HOLD PATCH  -  for ALVR v20.14.1 on Windows
  Version 1.0
===========================================================================

WHAT IT FIXES
-------------
In VRChat, when you put a controller down on your desk, your avatar's arm
drops to its side a few seconds later. Anything attached to that hand -- a
wrist menu, a held prop, a hand-parented UI -- goes with it.

With this patch, the hand simply STAYS where you left the controller.


HOW TO INSTALL
--------------
  1. Close SteamVR, the ALVR Dashboard, and VRChat. All the way closed.
  2. Double-click  INSTALL.bat
  3. Windows asks "Do you want to allow this app to make changes?" -> Yes
  4. Follow the messages. It takes about two seconds.

That's it. Start ALVR and SteamVR as usual.

To check it worked: in VRChat, set a controller on a table and wait 10-15
seconds. The hand should stay put instead of the arm dropping.


HOW TO UNDO IT
--------------
  Double-click  UNINSTALL.bat

Your original file is backed up automatically during install. If that backup
is ever missing, uninstall looks for another copy of the original driver and
checks it by SHA256 before using it -- it will never restore a file it cannot
verify. It looks in a "stock" folder next to this script, and in any other
ALVR version installed alongside yours.

If it finds nothing, it tells you to reinstall v20.14.1 from the ALVR
Launcher, which also replaces the driver and undoes the patch. Either way you
cannot end up stranded with a patched driver you can't remove.


JUST WANT TO CHECK WHAT'S INSTALLED?
------------------------------------
  Double-click  CHECK-STATUS.bat   (read-only, changes nothing, no admin)


===========================================================================
  HOW IT BEHAVES
===========================================================================

When your controller's tracking goes quiet, the hand freezes exactly where
it is, and all of that controller's inputs are released -- thumbstick to
centre, triggers and grips to zero, buttons unpressed.

The freeze lasts up to 5 minutes. After that the controller is reported as
genuinely disconnected, so one you deliberately switched off still goes away
properly.

Releasing the inputs is necessary because of what the freeze does. During a
dropout your headset stops sending button and stick updates, and SteamVR keeps
serving whatever arrived last -- that part is normal, and unpatched ALVR does
it too. It is harmless there only because the controller is reported as
disconnected, so games ignore its input.

This patch says the opposite: still connected, just not moving. That would
make the stale values count again -- a thumbstick held forward when tracking
dropped would keep walking you. So the freeze clears them itself.

One trade-off: if tracking blips while you are gripping something, you let go.


===========================================================================
  LONG DISCONNECTS? CHECK YOUR BATTERIES FIRST
===========================================================================

If a controller drops out for a long stretch -- tens of seconds or more --
and you have to press the Meta button to bring it back, that is almost
certainly a flat or failing battery, not this patch and not ALVR.

A controller running out of charge powers itself off. It wakes briefly when
you press a button, then drops again. This is easy to miss if you have
controller battery notifications turned off.

The driver log makes it easy to confirm -- see "READING THE LOG" below. A
freeze that ends with "hold timed out" rather than "source recovered" means
the controller was gone for the full five minutes, which is what a dead
battery looks like.


===========================================================================
  THINGS YOU SHOULD KNOW BEFORE RUNNING THIS
===========================================================================

* It only works on ALVR v20.14.1. The installer checks this and refuses to
  run on anything else, so it cannot break a different version. If you are
  on a newer ALVR, you need a patcher rebuilt for that version.

* It replaces ONE file:
      <your ALVR folder>\bin\win64\driver_alvr_server.dll
  Nothing else on your system is touched. No registry, no services, no
  installer, no background process, nothing added to startup.

* It needs Administrator ONLY because ALVR normally lives in Program Files,
  and Windows does not let ordinary programs write there.

* This is an unofficial, self-built, UNSIGNED file. It is not from the ALVR
  team, and they cannot support it. If you have a problem with ALVR while
  this is installed, uninstall the patch FIRST and check whether the problem
  is still there before reporting it to anyone.

* Windows SmartScreen or your antivirus may warn about an unsigned DLL or
  about the .bat files. That is expected for any self-built driver. If you
  do not trust the file, do not run it -- build it yourself instead; the
  exact source change is in the source\ folder.


WHAT IT ACTUALLY CHANGES (the short version)
--------------------------------------------
When your Touch controller goes to sleep, ALVR tells SteamVR the controller
was UNPLUGGED. VRChat responds to an unplugged controller by animating the
arm back to the avatar's default pose -- that is the arm drop.

The patch makes ALVR say "still connected, just not moving" instead, and
re-sends the last known position with all inputs released. After 5 minutes
it gives up and reports a real disconnect.

It is also careful not to interfere with ALVR's own choice between your
controller and its hand-tracking device: a device that does not currently
own your hand is never held.

The complete change is in
    source\alvr-idle-hold-v20.14.1.patch


READING THE LOG
---------------
Turn on log_to_disk in the ALVR Dashboard (Settings -> Extra -> Logging) and
restart SteamVR. The patch then records every freeze in session_log.txt:

  controller left: source inactive, holding last pose
      a freeze started

  controller left: source recovered after 412 ms, hold released
      tracking came back; that one lasted 412 ms

  controller left: hold timed out after 300000 ms, releasing device
      gone for the full 5 minutes -- check the battery

Turn log_to_disk back off when you are done; it writes a lot.


VERIFYING THE DOWNLOAD
----------------------
The file this ships should be exactly:

  driver_alvr_server.dll
  SHA256  28514EA68F12C825C1D756F67707E2D00F68CC9CCA2A4B0008F2DF7E6D11EC60
  Size    14,607,872 bytes

The original ALVR v20.14.1 file it replaces is:

  SHA256  5B2DC0012254FA3C45268ED655C3F589B2D460A62907C620670CFB5D22A48FA8
  Size    14,497,792 bytes

To check for yourself, in PowerShell:

  Get-FileHash .\driver_alvr_server.dll -Algorithm SHA256

The installer verifies these automatically and refuses to continue if
anything is wrong.


TROUBLESHOOTING
---------------
"Could not find ALVR automatically"
    Open PowerShell in this folder and give it the path yourself:
    .\Patch-ALVR.ps1 -InstallPath "C:\Program Files\alvr_launcher_windows\installations\v20.14.1"

"These are still running: vrserver..."
    SteamVR is still open. Close it (check the system tray), then retry.

"This driver is not the v20.14.1 build this patch was made for"
    You are on a different ALVR version. Do not force it.

"No backup, and no verified copy of the original driver on this PC"
    Reinstall v20.14.1 from the ALVR Launcher. That restores the original
    driver file and removes the patch. Your ALVR settings are kept.

ALVR will not start after installing
    Run UNINSTALL.bat. That puts the original file back.

A controller keeps disconnecting for long stretches
    Check its battery -- see the battery section above.

The patch disappeared after an ALVR update
    Expected -- updates replace the driver file. Run INSTALL.bat again, but
    only if the new version is still v20.14.1.


LICENSE / SOURCE
----------------
ALVR is by the alvr-org project:  https://github.com/alvr-org/ALVR
This is ALVR v20.14.1 with a local modification, built with the --gpl
option, which links GPL-licensed FFmpeg. The resulting binary is therefore
covered by the GPL, and the corresponding source is:

  * upstream:  https://github.com/alvr-org/ALVR  at tag v20.14.1
  * the change: source\alvr-idle-hold-v20.14.1.patch  (in this folder)

Build it yourself with:  cargo xtask build-streamer --release --gpl

Provided as-is, with no warranty of any kind.
