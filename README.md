# HP Victus 15-fa0xxx — macOS Tahoe

Target: **macOS Tahoe 26.7.1 (25G241)** with OpenCore.
Direction: **NullMoth NVIDIA driver for HDMI**, and the **XeGfx (WTLIntelGfx) i915 driver for the
internal Intel panel**. The XPS/NootedGreen stack and the copy-only NMX/NMIntelFB framebuffer are
no longer the target.

## Hardware

| Component | Hardware |
|---|---|
| Laptop / board | HP Victus 15-fa0xxx / 8A4F |
| CPU | Intel Core i7-12700H, 6 P-cores + 8 E-cores, 20 threads |
| Intel GPU | Alder Lake-P Iris Xe, `8086:46A6` |
| NVIDIA GPU | RTX 3050 Mobile, `10DE:25A2` |
| Display | CMN1521 internal eDP panel, connected to Intel; HDMI connected to NVIDIA |
| Audio | Realtek ALC245, `10EC:0245` |
| Keyboard | PS/2 |
| Touchpad | ELAN0788 I2C HID, `04F3:321A` |
| Wi-Fi | MediaTek MT7921, `14C3:7961` |
| Bluetooth | IMC/MediaTek USB, `13D3:3567` |
| Ethernet | Realtek RTL8111, `10EC:8168` |
| Storage | Samsung PM9A1 NVMe, `144D:A80A` |

## Current state

- **Tahoe boots** through the `MACEFI` OpenCore EFI.
- **NVIDIA:** installed with the NullMoth 1401 Mac app. The driver lives in `/Library/Extensions`
  (`NVRM`, `NVAccel`, `NVRMFB`, `NVRMAGDC`) and the AuxKC, never in the EFI. The HDMI output is
  the NVIDIA path. Ampere laptop validation is still listed as pending upstream; the internal
  panel is wired to Intel, so NVIDIA cannot drive it directly.
- **Intel internal panel:** the committed baseline still boots through the transitional Tiger Lake
  display fallback (`device-id`/`AAPL,ig-platform-id` spoof plus WhateverGreen, no acceleration);
  it stays until a real driver is proven. The target is **XeGfx** (`WTLIntelGfx` v0.0.47), i915 on
  XNU with a Metal accelerator, using the real `46A6` with no spoof and no WhateverGreen. Alder
  Lake is at the read-only probe: stage 2 passes on `46A6`; stage 4+ needs `adlp_guc_70.bin`
  linked into the kext, which upstream has not done yet.
- **Removed:** NootedGreen, the `-ngreen*`/`-allow3d`/`gfxrst=1` boot arguments, and the XPS
  acceleration references. The previous stack panicked in `IGAccelTask::withOptions` on this
  `46A6` 96 EU machine; the panic report is kept locally under `.downloads/panic-2026-10-29/`.
- **Wi-Fi:** `AirportMtkWlan` 1.5.1 Tahoe build enabled; not yet verified at runtime.
- **Audio / Bluetooth / sleep / brightness:** not verified. Audio needs separate AppleHDA work.

## EFI

- `EFI/` is the single source; git history is the rollback. Deploy with `tools/deploy-efi.sh`;
  never hand-edit the ESP.
- The 1401 changes are synced into `EFI/`: `AMFIPass.kext` 1.4.1, `IONDRVSupport` excluded,
  `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth`, `csr-active-config=0x0A53`, the NullMothSafe
  tools, and `HideAuxiliary=false`. `gfxrst=4` is set for WhateverGreen + NVIDIA.
- 27 enabled kexts (including AMFIPass), 9 SSDTs, 3 drivers. The private identity stays only in
  the deployed config and the git-ignored `EFI/OC/identity.plist`; the committed config keeps
  `REPLACEME…` placeholders.
- The 1401 app added two picker tools: **“1401: Remove NVIDIA driver”** and **“1401: Start once
  without NVIDIA driver”**. Use the first for a clean NVIDIA rollback; it restores the
  pre-install config.
- **Do not run `tools/deploy-efi.sh` from an unsynced tree.** It uses `rsync --delete`; a stale
  tree would remove AMFIPass/NullMothSafe and overwrite the 1401 config.

## Next: XeGfx on Alder Lake

The `nmintelfb` branch already has the EFI shape XeGfx needs. Keep `master` (NVIDIA/HDMI) as the
rollback and test on that branch:

- real `46A6`, no `device-id`/`AAPL,ig-platform-id` spoof, no WhateverGreen;
- `IONDRVSupport` present (XeGfxIntelFB links against it; the NVIDIA baseline excludes it);
- `XeGfx.kext` built from `WTLIntelGfx` v0.0.47+ and installed with its `tools/install.sh` into
  `/Library/Extensions` and the AuxKC, then one reboot so the collection includes it;
- `sudo kmutil load -b org.watchthelight.XeGfx`, then `sudo sysctl debug.xegfx_stage=2`. Stage 2
  only reads registers. Do not go past stage 3 until the Alder Lake GuC is wired in;
- report `ioreg -l -w0 -r -c XeGfxResident` and `sysctl -b debug.xegfx_log` to WTLIntelGfx #3.

Stage 2 has passed on a `46A6` (Legion Y9000P) and stages 1–3 on a `46A3` (another HP Victus
15-fa0xxx). Acceleration is blocked on the Alder Lake-P GuC firmware (`adlp_guc_70.bin`); the
kext links only the Meteor Lake blob today. Until that lands, the panel stays on the firmware
framebuffer, and scanout out of XeGfx is still a copy of the finished frame (zero-copy flip is on
its `xe-zerocopy-flip` branch). Build and test on macOS/APFS, use WTLGpuGuard/WTLBootDump for the
boot attempts, and do not deploy it as the default until the panel is proven.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are
git-ignored. macOS-side helpers for the XeGfx bring-up (read-only preflight, staged probe,
install/rollback) are on the utility drive under `scripts/xegfx/` — `/Volumes/macUtility/`
on macOS, `/run/media/sulthonuladib/macUtility/` from Linux. See
[references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
