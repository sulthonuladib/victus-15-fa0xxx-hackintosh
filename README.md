# HP Victus 15-fa0xxx — macOS Tahoe

Target: **macOS Tahoe 26.7.1 (25G241)** with OpenCore.
Direction: **NullMoth NVIDIA driver for HDMI**, and the **NullMoth NMIntelFB experiment for the
internal Intel panel**. The XPS/NootedGreen acceleration stack has been removed.

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
- **Intel internal panel:** currently on the transitional Tiger Lake display fallback
  (`device-id`/`AAPL,ig-platform-id` spoof plus WhateverGreen, no acceleration). The target is
  the NullMoth **NMIntelFB** test framebuffer, which uses the real `46A6` and copies NVIDIA frames
  to the panel. NMIntelFB is experimental and not installed by 1401.
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

## Next: NMIntelFB

The NMIntelFB experiment is on its own branch/config. It needs:

- the real Intel `46A6` (no Tiger Lake spoof) and no WhateverGreen;
- `IONDRVSupport` present (the NVIDIA baseline's block must be removed);
- `NMIntelFB.kext` built from the NullMoth source and installed in `/Library/Extensions`;
- `debug.nvaccel_igpu=1` so NVAccel exposes the Intel panel as head 4;
- the working NVIDIA/HDMI EFI kept as rollback.

NMIntelFB is a test framebuffer: display versions 12–20, phase 1 adopts the firmware-lit pipe,
and it is not shipped by the 1401 package. Build and test on macOS/APFS; do not deploy it as the
default until the panel is proven.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are
git-ignored. See [references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
