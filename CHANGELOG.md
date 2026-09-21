# Changelog

## 1.0 — 2026-09-21

First public release. Built against ALVR **v20.14.1**.

- Holds a controller's last pose while its tracking source is idle, instead of
  reporting the device as disconnected — which is what made VRChat animate the
  avatar arm back to its default pose.
- Releases all of that controller's inputs on entering a hold (thumbstick to
  centre, triggers and grips to zero, buttons unpressed), so nothing stays stuck
  live while the device is reported connected.
- Never holds a device that doesn't currently own its hand, so ALVR's runtime
  selection between the controller and hand-tracker devices is left intact.
- Holds for at most 5 minutes; a genuinely powered-off controller still
  disconnects.
- Logs each freeze and its duration to `session_log.txt` when `log_to_disk` is
  enabled.

Binary: `driver_alvr_server.dll`, SHA256
`28514EA68F12C825C1D756F67707E2D00F68CC9CCA2A4B0008F2DF7E6D11EC60`.
