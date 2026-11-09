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

- **WhateverXe (branch `whateverxe-adl`, 2026-11-10):** the `MACEFI` ESP now holds a **fresh
  OpenCore-Simplify tree**, not the 1401 base. WhateverXe 0.8.0 (Lilu plugin, kept directly
  after Lilu), **AMFIPass 1.4.1 Mod** (the b00t0x build from WhateverXe-Graphics `extras/`,
  byte-identical to that zip), `csr-active-config=0x803`, boot-args
  `-allow3d -disablegfxfirmware -igfxdvmt ctrsmt=full`. DVMT is fixed at 60 MB in this
  firmware, so the iGPU carries `framebuffer-patch-enable`/`framebuffer-stolenmem=0x3C00000`
  and has **no** `device-id`/`AAPL,ig-platform-id` spoof; WhateverGreen is gone. Input is
  VoodooPS2 (PS/2 keyboard) + VoodooI2C/VoodooI2CHID (ELAN0788), Wi-Fi is AirportMtkWlan
  (MT7921) and `BlueToolFixup` is carried for third-party BT — no MT7921 firmware loader
  exists, so Bluetooth itself stays unsupported.
- **Tahoe 26.7.1 is installed** on the APFS partition; the picker waits for a key (`Timeout=0`)
  with auxiliary entries visible.

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
  spoofs CPUID leaf 1 to Comet Lake (`0x0A5`), so the chip name would read Unknown; that is
  cosmetic. RestrictEvents needs `revpatch` to contain `cpuname` (boot-args shadow the NVRAM
  value), so boot-args are `revpatch=sbvmm,cpuname revcpu=1` with the name in NVRAM
  `revcpuname`. XCPM state not yet measured.
- **Wi-Fi:** `AirportMtkWlan` 1.5.1 Tahoe build enabled; not yet verified at runtime.
- **Audio / Bluetooth / sleep / brightness:** not verified. Audio needs separate AppleHDA work.

## EFI

- `EFI/` is the single source; git history is the rollback. Deploy with `tools/deploy-efi.sh`;
  never hand-edit the ESP.
- This branch's `EFI/` **is** the ESP tree: 28 enabled kexts (WhateverXe + AMFIPass Mod +
  VoodooPS2/I2C + AirportMtkWlan + BlueToolFixup), 11 SSDTs, 5 drivers, 0 tools. It keeps the
  OpenCore-Simplify defaults (`PickerMode=External` with OpenCanopy, `Timeout=0`,
  `HideAuxiliary=false`, `ScanPolicy=0`) and has no `Kernel/Block`, so `IONDRVSupport` loads —
  required by WhateverXe. The NVIDIA stack has no EFI presence here at all.
- The private identity stays only in the deployed config and the git-ignored
  `EFI/OC/identity.plist`; the committed config keeps `REPLACEME…` placeholders. Re-capture with
  `tools/deploy-efi.sh --capture` after any identity change.
- The 1401-era pieces on `master` (NullMothSafe tools, `IONDRVSupport` exclusion, `gfxrst=4`,
  `nvfb*`/`nvaccel*` boot-args, `csr-active-config=0x0A53`) do **not** exist on this branch.
  Rolling back to NVIDIA means switching back to `master` and redeploying from it.
- **Do not run `tools/deploy-efi.sh` from an unsynced tree.** It uses `rsync --delete`.
- Matching `ocvalidate` (1.0.9 `.linux` from the 1401 OpenCore zip) lives in `.downloads/ocvalidate`.
  `--check` ignores `EFI/OC/identity.plist`, which is git-ignored and never deployed.
## Next: WhateverXe on Alder Lake-P

Install order: EFI first (done on the ESP), then the WhateverXe Graphics pkg, then a restart so
AuxKC rebuilds. The pkg installs under `/Library` and never touches the EFI or SIP. Graphics
`0.4.1` is the match for WEX `0.8.0`; both must be updated together. Full disk access for the
installer is not needed, root is.

Known Alder Lake-P (`46A6`) trouble in upstream, from the WEX issue tracker:

- [#68](https://github.com/b00t0x/WhateverXe/issues/68) — an **0.8.0 regression on 46A6 eDP**
  loses acceleration (`FB0: FB has no memory allocated`). The reporter shows 0.7.0 kext +
  Graphics 0.4.1 working on the same macOS build we run. Keep `WhateverXe-0.7.0-RELEASE.zip`
  as the rollback kext.
- [#43](https://github.com/b00t0x/WhateverXe/issues/43) — the eDP link the firmware trained is
  torn down and retrained, and the panel stays dark on several Alder Lake laptops. The opt-in
  `-wex-edp-keep` lives only on the `nickk19/WhateverXe` fork (branch `display13-edp-keep-080`);
  neither 0.7.0 nor 0.8.0 main knows that argument.
- [#57](https://github.com/b00t0x/WhateverXe/issues/57) — the 60 MB stolen-memory path is exactly
  the one the README prescribes for our DVMT setting; nothing else to do there on bare metal.
- [#42](https://github.com/b00t0x/WhateverXe/issues/42), [#50](https://github.com/b00t0x/WhateverXe/issues/50)
  — freezes and eDP link loss under load on 46A6; treat long-run stability as unproven.

The usable debug switches in the 0.8.0 binary are `-wexdbg`, `-wexoff`, `-wex-noaccel`,
`-wex-adlp-load-only`, `-wex-adlp-readout`, `-wex-display-trace`, `-wex-display13-trace` and the
`-wex-adln-*` stage probes; there is no `-wex-edp-keep`.

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

After a stage-4 panic, boot normally and run
`sudo bash /Volumes/macUtility/scripts/xegfx/xegfx-collect-panic.sh`. It collects the panic,
probe, bootdump, build and EFI evidence into
`/Volumes/macUtility/xegfx-state/reports/<stamp>/`, updates `xegfx-state/STATE.txt`, writes a
redacted `REPORT-DRAFT.md`, and does not upload anything. For the next stage-4 attempt, use
`xegfx-stage4-trace.sh --yes` so the watchdog breadcrumb lands in NVRAM. Review the redacted
report before attaching it; `raw/` is local-only. The one-page macOS run note is
`/Volumes/macUtility/README.md`.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are
git-ignored. macOS-side tooling for the XeGfx bring-up (staged sources, GuC firmware, build, install,
probe) is on the utility drive under `scripts/xegfx/` — `/Volumes/macUtility/` on macOS,
`/run/media/sulthonuladib/macUtility/` from Linux; start with `RUNBOOK.md`. See
[references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
