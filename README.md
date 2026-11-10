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

- **Intel acceleration works (branch `whateverxe-adl`, 2026-11-10).** Measured on the internal eDP
  panel: `IntelAccelerator` 1, `AppleIntelFramebufferController` 1, `VRAM (Dynamic, Max)` 1536 MB,
  `Metal 2`, panel `1920x1080 @ 144 Hz`, `N97FramebufferBackendReady Yes` — no longer the 7 MB
  `IONDRVFramebuffer` fallback (report `report-20261110-101608`, utility drive). Stack: `MACEFI` carries a fresh
  OpenCore-Simplify tree, WhateverXe **0.7.0 built by us** (`420fcb5a…`), **AMFIPass 1.4.1 Mod**
  (byte-identical to WhateverXe-Graphics `extras/`) and WhateverXe Graphics **0.4.1** installed in
  `/Library` + AuxKC. `csr-active-config=0x0A03` (the `0x200` bit covers the Mod-signed AuxKC
  payloads). DVMT is fixed at 60 MB, so the iGPU carries `framebuffer-patch-enable` +
  `framebuffer-stolenmem=0x3C00000` and **no** `device-id`/`AAPL,ig-platform-id` spoof; no
  WhateverGreen.
- **Boot-args:** `-v debug=0x100 keepsyms=1 -allow3d -disablegfxfirmware -igfxdvmt ctrsmt=full
  -vi2c-force-polling -wex-edp-keep -wex-panel-fallback -wex-no-tc alcid=13 alcverbs=1`. Three are
  still bring-up switches: `-wex-edp-keep` keeps the firmware-trained panel link,
  `-wex-panel-fallback` enables the lenient VBT parse (duplicate DDI + duplicate internal child),
  `-wex-no-tc` drops the unused Intel TC1..4 routes. `-wex-display-trace` is back on only while the
  display glitches are being chased (it adds logging, nothing else); the three functional switches
  each need their own boot test, `-wex-edp-keep` last — WEX #43 says removing it can leave the panel
  dark. `alcverbs=1` is audio triage, not a permanent switch. **Never** add
  `-wex-adlp-readout`/`-wex-adlp-load-only`: WEX turns either into an "ADL-P load-only" boot that
  patches `probe`/`start` to reject both drivers.
- **Why 0.7.0 and not 0.8.0:** WEX #68 reports 0.8.0 losing the framebuffer allocation on `46A6`
  eDP (`FB0 has no memory allocated`). Our own patched 0.7.0 is the base; see the WhateverXe notes
  in `REFERENCES.md` for the five changes it carries.
- **Input / network:** VoodooPS2 (PS/2 keyboard) + VoodooI2C/VoodooI2CHID (ELAN0788), Wi-Fi
  `AirportMtkWlan` 1.5.0 (MT7921), `BlueToolFixup` for third-party BT — no MT7921 firmware loader
  exists, so Bluetooth stays unsupported.
- **Tahoe 26.7.1** runs from the APFS partition; the picker waits for a key (`Timeout=0`) with
  auxiliary entries visible.
- **Working area stays on the exFAT utility drive.** `macUtility` (`/Volumes/macUtility` on macOS,
  `/run/media/sulthonuladib/macUtility` on Linux) holds the WhateverXe artifacts, the CI zips, the
  `collect.sh`/`props.sh`/`vbt.sh` triage scripts and their reports. Keep using it: if a later
  change breaks the panel or the boot, the previous kext zip, the last good EFI state and the
  collected registry/VBT dumps are all there, so a rollback needs no network and no guesswork.
  Development continues from macOS on this branch; the ESP holds the deployed tree. Added
  2026-11-10: `wex-gfx-state.sh` (WEX watermark/DBUF/clock + underrun count since boot),
  `wex-glitchwatch.sh start|mark|stop` (kernel GPU log + display-link jitter around a glitch you
  just saw), `audio-verbs.sh` + `tools/alc-verb` (ALC245 codec dump through AppleALC),
  `bench/bench-cpu.sh` (same CPU benchmark on macOS and Linux), `bench/CPU-NOTES.md`,
  `dgpu-off/` (validated SSDT to power off the RTX 3050) and `reports/` (research write-ups).
- **Audio: HDA stack loads, no sound yet; codec triage armed (2026-11-10).** Tahoe does not ship `AppleHDA.kext`
  (`/System/Library/Extensions/AppleHDA.kext` is absent on this 26.7.1), so AppleALC alone cannot
  produce sound. The ESP carries **AppleALC 1.9.8** followed by **SimpleHDA 1.0.1** (a Lilu plugin
  that injects the original Apple HDA stack — no root patch, no system-volume write, no AuxKC
  rebuild) with `alcid=13`, the only HP layout AppleALC ships for ALC245. Measured: both plugins
  load, `AppleHDAController`/`AppleHDADriver`/`AppleHDAEngineOutput` each 1, `Built-in Output` is
  the default output (2 ch, Internal Speakers), the level controls sit at 87/87 and a 440 Hz tone
  does start the engine (`IOAudioEngineState` 1) — **but nothing is audible**. So the kernel path
  and CoreAudio are fine; the codec pin/amp path is not. Two facts worth keeping straight:
  `layout-id` 7 on HDEF is Lilu's `DefaultReportedLayoutId` (what AppleALC reports to AppleHDA, not
  the layout AppleALC picked); the applied layout is `alc-layout-id` = 13. Layout 13 drives
  speaker pin `0x17` from DAC `0x03` and headphones `0x21` from DAC `0x02` — the Victus wiring is
  unverified. The `SimpleHDA-HAL-1.0.1.pkg` bundle is installed at
  `/Library/Audio/Plug-Ins/SimpleHDA/AppleHDAHALPlugIn.bundle` but SimpleHDA only detects it at
  boot (`SimpleHDAHALMode` was still `not-installed` on the 2026-11-10 session), hence the
  `alcverbs=1` (now in the boot-args). Next boot publishes AppleALC's
  `ALCUserClientProvider`, so `macUtility/whateverxe/audio-verbs.sh` can dump every widget's
  `config_default`, connection list, pin sense/EAPD and amp gain without a reboot loop; the plan is
  to find the codec's real speaker pin instead of trusting a layout. That dump settled it: pin
  `0x14` is the fixed internal speaker (BIOS default `0x90170110`, EAPD on) and its only source is
  **DAC `0x02`**, `0x17` is a 4-way mux (`0x02/0x03/0x06/0x08`), `0x21` takes `0x02/0x03`, and the
  pin amps are mute-only (`AMP_OUT_CAP` `0x80000000`, no gain). Layout 13 drives `0x17 <- DAC 0x03`
  — a muted, un-enabled pin fed by an idle converter, which is exactly the silence. Of the three
  layouts AppleALC ships for ALC245, **layout 11** is the only one whose speaker path is
  `0x14 <- 0x02`, so the boot-args now say `alcid=11`. The reason the codec never made a sound is
  one step up from that: with layout 13 the driver powers up **only** its own converter
  (`GET_POWER_STATE` on `0x03` = D0 while playing, `0x02` and `0x14` stay **D3**) and D3 passes no
  audio, so the real speaker path was powered down as well as muted. Forcing the AFG, both DACs and
  the pins to D0 and re-asserting `0x14` unmuted/enabled made the codec's own beep generator
  audible (measured 19:48, on the wire: `SET_POWER_STATE 0`, `SET_AMP_GAIN_MUTE 0xD07f`,
  `SET_PIN_WIDGET_CONTROL 0x40`, `SET_EAPD_BTLENABLE 0x02`) — so the analog chain, speakers
  included, is fine and only the path/power selection was wrong. Platforms11.xml carries Amp
  configs on both `0x14` and `0x02`, so the driver should unmute and power them itself once it
  selects that path. Microphone and headphone-jack switching are
  not verified. Requires `Kernel > Quirks > DisableLinkeditJettison=true` (set).
- **Display off does not come back (2026-11-10, on the pre-WM-fix kext).** With `displaysleep 10`
  the panel blanked at 18:56 and never returned; the logs show a pipe-A underrun at 18:56:03 and
  then 12208 `WindowServer ... [com.apple.CoreDisplay] [ERROR] - Fallback GPU Display Pipe
  transaction submission failed` / `Transaction Target State` / `DisplaySurface Size: (1920x1080)`
  in 16 minutes until the machine was force-powered-off. The first boot on the WM fix (19:15) has
  **0 underruns and 0 CoreDisplay errors**, but display-off/on has not been exercised on it yet.
  Until it is, `pmset displaysleep 0` keeps the panel on (sleep was already 0). If the fix does not
  cover it, the known workarounds for this class are `-nodisplaysleepDC6 -noDC9 dc6config=0`
  ([#63](https://github.com/b00t0x/WhateverXe/issues/63)).
- **Unverified:** brightness keys, sleep/wake (WEX calls sleep experimental), long-run
  stability under load (WEX #42/#50 on `46A6`), and external outputs from the iGPU (HDMI is wired
  to the NVIDIA dGPU on this laptop).

- **Not installed on this install:** no NullMoth/1401 NVIDIA driver, no WhateverGreen, no
  XeGfx, no XPS stack. This is a scratch Tahoe install whose only graphics stack is WhateverXe,
  and it needs `IONDRVSupport` and no spoof. The NVIDIA and XeGfx history lives on `master`.
- **Display: underruns, traced to a WEX certificate bug (2026-11-10).** What the user sees as
  flicker/lag is measurable: `[IGFB][ERROR][DISPLAY] Display Pipe Underrun occurred on pipe(s) A`
  2491 times in one 59-minute boot, in bursts (one minute alone had 1228) with `DBUF Pipe A
  Plane 0` holding the whole bank (`start 40 end 1023 size 984`). The kernel side checks out: the
  panel link is 4 lanes at **HBR** (0x0A) with 342.06 MHz pixel clock = **95 %** of HBR×4, CDCLK is
  the firmware's **179.2 MHz**, and WEX never programs the watermarks itself. Root cause found in
  `WhateverXe/kern_display13_wm.hpp:289`: `clockFits()` compares the plane pixel rate against
  `nativeHz/2`, but `nativeHz` is already **2×CDCLK** by the donor ABI, so it demanded
  `pixelHz <= CDCLK` — twice as strict as gen12, where i915's `intel_pixel_rate_to_cdclk()` divides
  by 2. 342.06 MHz against 179.2 MHz therefore failed, which latched `watermarkFaulted`/
  `dbuf.faulted` and froze `wmPending` for the session (`N97FBPrimaryWMProgram` = *Unavailable*,
  `N97FBWMLatch` = *Input*), blocking watermark retirement and any later DBUF/clock re-layout.
  Branch `gfx-wm-fix` carries the corrected comparison plus its unit test (CI run 42809313867,
  binary `4cd2f40e…`); it is deployed and waiting for a boot test. Metal support is **Metal 2**.
- **Metal 3: the flag is a 2-byte patch, the features are the work (2026-11-10).** `Metal3` is one
  instruction in `AppleIntelTGLGraphicsMTLDriver`: `movq $0x2711` at file offset `0x22953`, and that
  immediate is the only `0x2711` in the binary (`0x22957`). Patching those two bytes to `0x2712`,
  re-signing ad-hoc and reloading makes the device report `Metal3 = yes` — measured with a plain CLI
  process loading the bundle, so AMFIPass already covers the signature side. What the flip does not
  buy, measured with it on: `libraryTypeDynamic` compiles, `[[mesh]]`/`[[object]]` shader functions
  compile, but **mesh pipeline creation fails inside our own compiler layer** — `Xe compiler
  unsupported serialized request` from `XeCompilerAdapter.bundle/.../adapter.dylib` — and binary
  archives still report `no target architecture`. Ray tracing is absent because Xe-LP has no RT
  units. So the remaining Metal 3 work is two own-layer jobs, not an Apple one: teach the adapter the
  mesh serialized request (its source is unpublished, so that is RE work on the request dispatch),
  and give the plugin a target architecture/archive implementation. Until then the flag stays off
  (`/Volumes/macUtility/whateverxe/mtl3-backup/restore-stock.sh`), because a Metal 3-flagged device
  sends apps down paths the driver cannot finish. Upstream #69 wants exactly these numbers.
- **CPU:** XCPM via `SSDT-PLUG-ALT` (`plugin-type` `C000`), `ProvideCurrentCpuInfo` true and
  CpuTopologyRebuild enabled. OpCore-Simplify spoofs CPUID leaf 1 to Comet Lake (`0x0A5`); that is
  cosmetic for the chip name. RestrictEvents keeps `revpatch=sbvmm,cpuname` + `revcpu=1` with
  `revcpuname` in NVRAM. The **2.68 GHz** in About This Mac is the nominal value macOS publishes
  (`hw.cpufrequency` = min = max), not a cap: XCPM lists P-states to **4700 MHz**
  (`CPUPStates`, `hard_plimit_max_100mhz_ratio` 47) and `pmset -g therm` reports no clamp. Measured
  2026-11-10 with `powermetrics`: 3646 MHz peak on one busy thread, 3494 MHz with six, 2.5 GHz
  system average on all 20 threads — i.e. the top turbo bins (3.7–4.7 GHz) are never used, which is
  the open CPU-PM question (`bench/CPU-NOTES.md`).
- **Wi-Fi:** `AirportMtkWlan` 1.5.0 (MT7921, kernel 25.x builds only) enabled; not yet verified at
  runtime on this install. Bluetooth (`13D3:3567`) has no macOS firmware loader — `MtkBt` matches
  MT7925 ids only — so `BlueToolFixup` is present but BT is not expected to work.
- **Audio / sleep / brightness:** not verified; WEX calls sleep/wake experimental.

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
- Matching `ocvalidate` lives in `.downloads/ocvalidate-macos/` (macOS, from the OpenCore 1.0.8
  RELEASE zip — the newest release, and the one our config validates against) and
  `.downloads/ocvalidate-linux/` (when running the script from Omarchy); the script picks the host's
  build. `--check` ignores `EFI/OC/identity.plist`, which is git-ignored and never deployed.
- `tools/deploy-efi.sh` runs on both sides: `findmnt` on Linux, `mount`/`df` on macOS, where the
  target is `/Volumes/MACEFI`. It still refuses non-FAT32 volumes and the volume holding the running
  system, and it is the only supported way to write the ESP.
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
