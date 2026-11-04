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
- **Intel internal panel:** the deployed `MACEFI` config is now the XeGfx test shape (real `46A6`,
  no `device-id`/`AAPL,ig-platform-id` spoof, no WhateverGreen, `IONDRVSupport` unblocked, no
  `gfxrst=4`), deployed 2026-11-04 from the `nmintelfb` branch. `master` keeps the transitional
  Tiger Lake fallback as the rollback. XeGfx itself is not installed yet: Alder Lake is at the
  read-only probe: stages 1-3 pass on this machine (real `46A6`, PCH `8086:5182`, stolen
  `0x7c800000` 60 MiB, pipe A lit), and stage 4+ needs `adlp_guc_70.bin`, which we patch in
  locally (GuC v70.49.4); upstream has not linked it.
- **Removed:** NootedGreen, the `-ngreen*`/`-allow3d`/`gfxrst=1` boot arguments, and the XPS
  acceleration references. The previous stack panicked in `IGAccelTask::withOptions` on this
  `46A6` 96 EU machine; the panic report is kept locally under `.downloads/panic-2026-10-29/`.
- **CPU:** XCPM with `plugin-type` from `SSDT-PLUG-ALT` (`C000`), `ProvideCurrentCpuInfo` and
  CpuTopologyRebuild (E-cores as P-core SMT siblings by default). The 1401/OpCore-Simplify config
  spoofs CPUID leaf 1 to Comet Lake (`0x0A5`), so the chip name reads generic/Unknown; that is
  cosmetic (RestrictEvents `revcpu=1 revcpuname=…`). XCPM state not yet measured.
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
- The ESP currently holds the `nmintelfb` config, so run `--check`/deploy from that branch (a
  `git worktree` works) or from `master` when rolling the fallback back. Matching `ocvalidate`
  (1.0.9 `.linux` from the 1401 OpenCore zip) lives in `.downloads/ocvalidate`.

## Next: XeGfx on Alder Lake

The ESP already boots the `nmintelfb` config; `master` keeps the fallback as rollback. The macOS
build sequence, prerequisites, staged sources and troubleshooting live on the utility drive:
`scripts/xegfx/RUNBOOK.md`, driven by `xegfx-run.sh kernel | probe | metal`. Nothing needs
cloning there: 331 MB of pinned sources and the GuC firmware are staged.

Local addition over upstream v0.0.47: `adlp_guc_70.bin` (GuC v70.49.4 from linux-firmware, whose
i915 blobs now live under `i915/`) is embedded and copied into `Resources/` by a patch to
`tools/link.sh` (`xegfx-patch-guc.sh`). Upstream does not do this, and without it stage 4 has no
GuC on `46A6`. The Metal plugin and translator also need our install step; upstream's
`tools/install.sh` does not place them in `/Library/GPUBundles/NVMTLDriver.bundle`.

Order: Phase A kernel → reboot → load → stages 1-3, then 4 with `--yes`; Phase B builds the
accelerator/AGDC/framebuffers + plugin/translator + libdrm/Mesa ANV → install → reboot → stage 4
→ desktop handover. Report results to WTLIntelGfx #3. Scanout is still a copy into the firmware
framebuffer (zero-copy flip is on upstream's `xe-zerocopy-flip` branch); do not make XeGfx the
default until the panel is proven.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are
git-ignored. macOS-side tooling for the XeGfx bring-up (staged sources, GuC firmware, build, install,
probe) is on the utility drive under `scripts/xegfx/` — `/Volumes/macUtility/` on macOS,
`/run/media/sulthonuladib/macUtility/` from Linux; start with `RUNBOOK.md`. See
[references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
