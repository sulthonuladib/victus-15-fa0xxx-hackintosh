# HP Victus 15-fa0xxx — macOS Tahoe

Target: **macOS Tahoe 26.7.1 (25G241)**, OpenCore 1.0.8, SMBIOS `MacBookPro16,2`.
This branch runs the **Intel Xe iGPU** with WhateverXe (WEX) and drives the internal eDP panel; the
NVIDIA dGPU is powered off and no longer enumerates. The NVIDIA/NullMoth and XeGfx histories live on
`master`; see [REFERENCES.md](REFERENCES.md).

## Hardware

| Component | Hardware |
|---|---|
| Laptop / board | HP Victus 15-fa0xxx / 8A4F |
| CPU | Intel Core i7-12700H, 6 P-cores + 8 E-cores, 20 threads |
| Intel GPU | Alder Lake-P Iris Xe, `8086:46A6`, 96 EU |
| NVIDIA GPU | RTX 3050 Mobile `10DE:25A2` + HDA `10DE:2291` — **off, not enumerated** |
| Display | CMN1521 internal eDP, 1920x1080 @ 144 Hz, on the Intel GPU (HDMI is wired to the NVIDIA) |
| Audio | Realtek ALC245, `10EC:0245` |
| Keyboard / touchpad | PS/2 / ELAN0788 I2C HID `04F3:321A` |
| Wi-Fi / Bluetooth | MT7921 `14C3:7961` / IMC-USB `13D3:3567` (no firmware loader: BT unsupported) |
| Ethernet / storage | RTL8111 `10EC:8168` / Samsung PM9A1 `144D:A80A` |

## Current state (measured 2026-11-10, 21:00 boot)

- **Internal panel accelerated**: `IntelAccelerator` 1, `AppleIntelFramebufferController` 1, VRAM
  `1536 MB` dynamic, **Metal 2**, 1920x1080 @ 144 Hz on the firmware-trained HBR x4 eDP link.
- **Audio works**: internal speakers, `Built-in Output` default, 2 ch. ALC245 layout **11**
  (`0x14 <- DAC 0x02`), `alcid=11`.
- **dGPU off**: `SSDT-DGPU-POFF2` asserts PERST# and drops the rail at `_INI`; `01:00.0` is gone
  from `lspci`, `ioreg` has no `10de:25a2`, System Information shows Intel only.
- **Display-pipe underruns**: the `clockFits()` fix (below) is deployed and the WM certificate now
  latches (`N97FBWMLatch`/`N97FBDBUFLayout` = *Complete*, failure records absent). Earlier boots
  produced up to 2491 `Display Pipe Underrun occurred on pipe(s) A` events per boot and a
  display-off black screen; re-measure with `wex-gfx-state.sh`.
- **Input / network**: VoodooPS2 keyboard, VoodooI2C/VoodooI2CHID touchpad, `AirportMtkWlan` 1.5.0
  for Wi-Fi. Bluetooth has no MT7921 firmware loader, so `BlueToolFixup` is present but BT is not
  expected to work.
- **CPU**: XCPM on, P-state table to 4700 MHz, no thermal clamp; measured peak 3646 MHz on one
  thread and 2.5 GHz system average across 20 threads — the top turbo bins are unused (see CPU).
- **Not verified**: sleep/wake, display off/on, brightness keys, long-run stability, microphone
  and headphone-jack switching.

## Versions and local patches

| Piece | Version | Notes |
|---|---|---|
| OpenCore | 1.0.8 | config validates with the 1.0.8 `ocvalidate`; 5 drivers, 12 ACPI tables, 30 kexts |
| WhateverXe (kext) | **0.7.0, our build** | binary `4cd2f40e…`, CI run 42809313867; deployed in `EFI/OC/Kexts/WhateverXe.kext` |
| WEX source | fork `sulthonuladib/WhateverXe`, branches `adlp-panel-route` + `wm-cdclk-half` | see "Patches we carry" |
| WhateverXe Graphics | 0.4.1 | installs `AppleIntelTGLGraphics*` 16.0.32 + `AppleIntelTGLCompat` 0.8.0 into `/Library` + AuxKC, and the 16.0.32 GPU bundles into `/Library/GPUBundles` |
| AMFIPass | 1.4.1 **Mod** | from WhateverXe-Graphics `extras/`; never load it together with upstream AMFIPass |
| AppleALC / SimpleHDA | 1.9.8 / 1.0.1 | order Lilu -> AppleALC -> SimpleHDA; `alcid=11`; SimpleHDA-HAL pkg installed |
| Lilu | 1.7.x | required by AppleALC, SimpleHDA, WEX, AirportMtkWlan |
| SIP | `csr-active-config=0x0A03` | the `0x200` bit covers the Mod-signed AuxKC payloads |
| DVMT | 60 MB (fixed by firmware) | iGPU keeps `framebuffer-patch-enable` + `framebuffer-stolenmem=0x03C00000`, no spoof |

Boot-args today:

```
-v debug=0x100 keepsyms=1 -allow3d -disablegfxfirmware -igfxdvmt ctrsmt=full -vi2c-force-polling
-wex-display-trace -wex-edp-keep -wex-panel-fallback -wex-no-tc alcid=11 alcverbs=1
```

- `-wex-edp-keep`: keep the firmware-trained panel link (removing it retrains and is documented to
  leave ADL-P/TGL panels dark — #43).
- `-wex-panel-fallback`: lenient VBT parse (duplicate DDI, duplicate internal child, lowest internal
  DDI). `-wex-no-tc`: drop the unused TC1..4 routes so `wrapDisplay13FramebufferStart()` stops
  refusing with `ADLPFBTCUnavailable`.
- `-wex-display-trace`: logging only, kept while display issues are being chased.
- `alcverbs=1`: publishes AppleALC's `ALCUserClientProvider` so `alc-verb` can read the codec.
- **Never** add `-wex-adlp-readout`/`-wex-adlp-load-only`: WEX turns either into an "ADL-P load-only"
  boot that patches `probe`/`start` to reject both drivers.

### Patches we carry in WEX

Upstream 0.8.0 loses the framebuffer allocation on `46A6` eDP ([#68](https://github.com/b00t0x/WhateverXe/issues/68)),
so the base is 0.7.0 plus the nickk19 `display13-edp-keep` handoff work, and on top of that:

1. `Display13: treat VBT panel type 0xFF as panel type 0` — our VBT block 40 says "select by EDID".
2. `Adopt the BDB-advertised internal eDP DDI when the LFP facts are unusable`, plus
   `Make the panel-route fallback opt-in` and `take the lowest internal DP DDI, not a unique one`.
3. `ADL-P eDP bring-up: the #35 blockers plus the TC-gate fix` (CDCLK controller gate on the first
   FB0 modeset; TC1..4 routes dropped).
4. **`clockFits()` compares against 2xCDCLK, not CDCLK.** `nativeHz` is twice the Linux CDCLK by
   the donor ABI, and gen12 emits two pixels per CDCLK (`intel_pixel_rate_to_cdclk()` divides by 2
   for `DISPLAY_VER>=10`). The old test demanded `pixelHz <= CDCLK`, so our 342.06 MHz eDP pixel
   clock on 179.2 MHz CDCLK was declared impossible, which latched `watermarkFaulted`/`dbuf.faulted`
   and froze `wmPending` for the session — the watermark retirement path and every later DBUF/clock
   re-layout stayed blocked. Fixed in `kern_display13_wm.hpp` with its unit test
   (`tests/display13_wm.cpp`).

Building WEX: there is no full Xcode on this machine, so builds go through the fork's
`.github/workflows/ci.yml` (`macos-15-intel`, RELEASE artifact) — see "Reproducing the install".

### ACPI tables we add

`SSDT-ALS0`, `SSDT-SBUS`, `SSDT-EC`, `SSDT-GPI0`, `SSDT-MCHC`, `SSDT-PLUG-ALT` (`plugin-type`
`C000`), `SSDT-PNLF`, `SSDT-RTCAWAC`, `SSDT-USB-Reset`, `SSDT-USBX`, `SSDT-XOSI`, and
**`SSDT-DGPU-POFF2`**.

`SSDT-DGPU-POFF2` replays the MMIO tail of the firmware's own `\_SB.PC00.PEG1.POFF()`
(`\PIN.ON(RSTG)` to assert PERST#, then `\PIN.OFF(PWRG)` to drop the rail when `GPPR()==1`) from
`_INI`, using the firmware's GNVS pin numbers, and sets `\_SB.PC00.PEG1.PEGP._STA = 0`. Two things
were learned the hard way and are worth not re-learning:

- the firmware `POFF()` **aborts** when called from `_INI`: its first statement writes
  `\_SB.PC00.LPCB.EC0.GFXT`, and the ACPI EC handler is not installed that early (`AE_NOT_EXIST`), so
  it never reaches the GPIO calls. `\PIN` -> `\_SB.SGOV` is a `SystemMemory` OperationRegion write to
  `PADCFG_DW0`, i.e. pure MMIO, and works at any time.
- `_STA = 0` alone does **not** hide a PCI function: macOS enumerates from the bridge's hardware
  scan. Measured with the table loaded and its `_INI` visibly running: `01:00.0` still answered.
  Only PERST#/rail removal makes the device disappear.

## Reproducing the install

### 1. EFI

`EFI/` is the single source and git history is the rollback; never hand-edit the ESP.

```sh
tools/deploy-efi.sh              # validate EFI/, rsync to MACEFI, splice the private identity
tools/deploy-efi.sh --check      # read-only: is the ESP EFI/ plus only the identity?
tools/deploy-efi.sh --capture    # read identity from the ESP into EFI/OC/identity.plist (git-ignored)
```

It runs on both sides: `findmnt` on Linux, `mount`/`df` on macOS (`/Volumes/MACEFI`). It refuses
non-FAT32 targets and the volume holding the running system, and uses `rsync --delete`, so do not run
it from an unsynced tree. `ocvalidate` must match the ESP's OpenCore version and is host-specific:
`.downloads/ocvalidate-macos/` (1.0.8, from the OpenCore RELEASE zip) and
`.downloads/ocvalidate-linux/`; the script picks by `uname -s`.

The identity (serial, MLB, ROM, UUID) lives only in the deployed `config.plist` and the git-ignored
`EFI/OC/identity.plist`; the committed config keeps `REPLACEME…` placeholders.

### 2. WhateverXe kext (CI build)

```sh
cd .references/WhateverXe                  # clone of sulthonuladib/WhateverXe, or any checkout
git checkout adlp-panel-route             # panel routing; wm-cdclk-half adds the WM fix
gh workflow run ci.yml --ref <branch> -R sulthonuladib/WhateverXe
gh run watch <run-id> -R sulthonuladib/WhateverXe --exit-status
gh run download <run-id> -R sulthonuladib/WhateverXe -n Artifacts -D /tmp/wex-art
unzip -q /tmp/wex-art/WhateverXe-0.7.0-RELEASE.zip -d /tmp/wex-rel
# replace EFI/OC/Kexts/WhateverXe.kext with /tmp/wex-rel/WhateverXe.kext, commit, deploy, reboot
```

Keep WEX and WhateverXe Graphics **version-paired** (0.7.0 / 0.4.1 today). Record the binary hash
(`shasum -a 256 WhateverXe.kext/Contents/MacOS/WhateverXe`) in the commit message; the deployed
build is `4cd2f40e…`.

### 3. WhateverXe Graphics (user space)

```sh
sudo installer -pkg WhateverXe-Graphics-0.4.1.pkg -target /     # rebuilds AuxKC
```

It installs `AppleIntelTGLGraphics.kext`, `…Framebuffer.kext`, `AppleIntelTGLCompat.kext` into
`/Library/Extensions`, the Metal/GL/VA bundles plus `XeCompilerAdapter` into `/Library/GPUBundles`,
and rebuilds `AuxiliaryKernelExtensions.kc`. The driver bundles are Apple's **16.0.32** (Big Sur
era) — that is why Metal is Metal 2 and why Metal 3 needs work (below). Backup before any experiment:
`/Volumes/macUtility/whateverxe/mtl3-backup/`.

### 4. Audio

Order matters: **Lilu → AppleALC 1.9.8 → SimpleHDA 1.0.1**, `Kernel > Quirks > DisableLinkeditJettison
= true`, `alcid=11`. Tahoe ships no `AppleHDA.kext`; SimpleHDA injects Apple's HDA stack so AppleALC
can apply a layout. Optionally install `SimpleHDA-HAL-1.0.1.pkg` (`/Library/Audio/Plug-Ins/SimpleHDA`).
`alcid=11` is the only shipped ALC245 layout whose speaker path is `0x14 <- DAC 0x02`, which is what
this codec exposes (`0x17` is a 4-way mux, pin amps are mute-only, `AMP_OUT_CAP 0x80000000`).

### 5. Post-install verification (utility drive)

```sh
sudo bash /Volumes/macUtility/whateverxe/wex-gfx-state.sh   # WM/DBUF status + underruns since boot
sudo bash /Volumes/macUtility/whateverxe/audio-verbs.sh     # ALC245 widget/pin/amp dump via alc-verb
sudo bash /Volumes/macUtility/whateverxe/props.sh           # WEX preflight registry properties
sudo bash /Volumes/macUtility/whateverxe/wex-glitchwatch.sh start   # then `mark` at a visible glitch
ioreg -l | grep -c 25a2                                     # must be 0 (dGPU gone)
bash /Volumes/macUtility/whateverxe/bench/bench-cpu.sh      # same CPU bench as on the Linux side
```

## Known issues and next work

- **Metal 3**: the family flag is a 2-byte patch in `AppleIntelTGLGraphicsMTLDriver`
  (`movq $0x2711` at offset `0x22953`, immediate at `0x22957`, the only `0x2711` in the binary).
  Patching it to `0x2712` + ad-hoc re-signing makes the device report `Metal3 = yes` (measured), and
  `libraryTypeDynamic` and `[[mesh]]`/`[[object]]` compilation still work — but **mesh pipeline
  creation fails in our own layer** (`Xe compiler unsupported serialized request` from
  `XeCompilerAdapter/…/adapter.dylib`) and binary archives say `no target architecture`. Ray tracing
  is absent because Xe-LP has no RT units. The flag is kept **off**: a Metal 3-flagged device sends
  apps down paths the driver cannot finish. `mtl3-backup/restore-stock.sh` restores the stock bundle;
  `install-metal3.sh` re-applies the experiment. Next step there is RE of the adapter's request
  dispatch, then the archive/target-architecture layer.
- **Patched Metal driver now runs the XPS driver fixes (branch `metal3-xps`, 2026-11-10).** Using
  `JulioNectar`'s validated patch table (`tools/metal3/apply-xps-patches.py`, offsets/bytes from
  their `macos/mtl17-patches.json`), the live 16.0.32 bundle carries patches **2–9**: ignore the
  kernel's IOSurface compression flag, no render-target fast clear, no dual-SIMD8 clear PS, no
  fast-clear write PS state, the L3 immediate `0x88000020`→`0xd0000020`, `programClearPipeline`
  always emits a disabled VS and marks VS dirty, and **the 96 KB-per-command-buffer POSH leak fix
  (`0x7ed87`)**. Patches 0/1 (their `libxedrv` injection, needs their header layout) and 10 (their
  `xe.bundle` compiler path) are deliberately not applied — WhateverXe already adds its own load
  commands and ships its own compiler adapter. Measured right after install: `WindowServer` RSS was
  **6.0 GB after 49 min**, i.e. the leak is real on this machine, but the fix only loads when
  WindowServer restarts; verify with `tools/metal3/metal3-bundle.sh status` after a logout/reboot.
  `restore` puts the stock bundle back from `macUtility/whateverxe/mtl3-backup`. With
  `amfi_get_out_of_my_way=1` in the boot-args the ad-hoc bundle loads in WindowServer (without it the
  GUI dies on library validation — that is the black screen of 2026-11-10 22:01, recoverable only
  over SSH). Measured across the 22:19 boot: WindowServer starts at ~140 MB and grows **2.7 MB/min**
  with a flattening curve, against **196–530 MB/min** (7.5 GB in under an hour) on the stock bundle.
  That leak fix is the single biggest usability win on this stack so far. A **logout does not
  reload it**: Tahoe keeps the same WindowServer (pid 205 started at boot while loginwindow restarted
  70 min later), so the leak kept running at 196–332 MB/min and reached 7.5 GB — `metal3-bundle.sh
  watch N` measures it. The patched code only takes effect after a `WindowServer` restart or reboot.
- **Metal 3 hook layer (branch `metal3-xps`).** Our own dylib now loads into every Metal process
  without touching the Mach-O header: `impostor.dylib` is renamed `impostor-orig.dylib` and replaced
  by `tools/metal3/hook.m` built with install name `@rpath/impostor.dylib`, which `dlopen`s the
  original from its own directory and then swizzles `MTLIGAccelDevice`. (The alternative — adding an
  `LC_LOAD_DYLIB` — does not fit: 27 commands, `sizeofcmds 0x10b0`, header ends at `0x10d0`; and
  repointing the MPS command breaks its 9 strong imports, while a symlink at the shortened path is
  refused by dyld.) It logs to `/var/tmp/xedrv-hook-<pid>.log`, pass-through only, and prints what
  the driver is asked: `[family] 5001 -> 0`, `[archive] … no target architecture`,
  `[mesh] … unsupported serialized request`. That log is the map for the next step: satisfy
  `-architecture` for binary archives, and decide whether `libigc-tgl` can compile a mesh stage at
  all before writing any emulation.
- **Display off/on** is unproven. With the pre-fix kext a display-off ended in thousands of
  `WindowServer … Fallback GPU Display Pipe transaction submission failed` lines and a dead panel, so
  `pmset displaysleep 0` is set until wake is tested on the current kext.
- **CPU turbo**: `About This Mac` shows 2.68 GHz because macOS publishes that nominal
  (`hw.cpufrequency` = min = max); XCPM itself lists P-states to 4700 MHz and `pmset -g therm` shows
  no clamp. Measured peaks are 3646 MHz (1 thread) / 3494 MHz (6) / 2.5 GHz average (20 threads), so
  the top bins are unused. The promising lead is **XE-PM** from the XPS/IrisXe stack (hybrid HWP
  rescale in ~78.7 MHz units, EPP, C8/C10) — +33 % single-core there, patched against our exact
  build; see [REFERENCES.md](REFERENCES.md).
- **Stability**: WEX freezes and eDP link loss under load are open upstream (#42/#50); treat long-run
  stability as unproven.

## Where the working material lives

`macUtility` — `/Volumes/macUtility` on macOS, `/run/media/sulthonuladib/macUtility` on Linux:

| Path | What |
|---|---|
| `WhateverXe-*.zip`, `WhateverXe-Graphics-*.pkg`, `SimpleHDA-*.zip`, `AppleALC-*.zip` | pinned payloads |
| `props.sh`, `collect.sh`, `vbt.sh`, `audio-check.sh` | original triage scripts |
| `audio-verbs.sh` + `tools/alc-verb` | codec dump/verbs through AppleALC |
| `wex-gfx-state.sh`, `wex-glitchwatch.sh`, `tools/jitter` | WEX/watermark/underrun state, glitch capture |
| `bench/bench-cpu.sh`, `bench/CPU-NOTES.md` | CPU benchmark shared with the Linux side + findings |
| `dgpu-off/` | dGPU research: DSDT/SSDT disassembly, `iasl`/`acpiexec`, the SSDT variants |
| `mtl3-backup/` | stock + Metal 3-flagged MTL bundles, probes, install/restore scripts |
| `reports/` | research write-ups (WEX display/glitch research, Metal 3 feasibility) |
| `tools/iasl`, `tools/acpiexec` | ACPICA built locally (no Homebrew) |

Reference sources are read-only checkouts under `.references/` (git-ignored): `AppleALC` 1.9.8 and
our `WhateverXe` fork. `~/personal/OpCore-Simplify/` is the EFI generator this install came from.

## Next: XeGfx on Alder Lake (master branch)

The XeGfx (`WTLIntelGfx`) path — Linux i915 on XNU with a NullMoth-derived Metal accelerator — is the
long-term goal for real Intel acceleration and lives on `master` with its own runbooks
(`scripts/xegfx/` on the utility drive). It needs the real `46A6`, `IONDRVSupport` present, no
WhateverGreen, and no spoof. Alder Lake is probe-only until `adlp_guc_70.bin` (GuC v70.49.4) is
linked. See [REFERENCES.md](REFERENCES.md).
