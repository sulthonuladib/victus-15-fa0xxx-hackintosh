# References and attribution

## Components used by this EFI

| Project | Contribution |
|---|---|
| [OpenCore](https://github.com/acidanthera/OpenCorePkg) | Bootloader |
| [Lilu](https://github.com/acidanthera/Lilu), [WhateverGreen](https://github.com/acidanthera/WhateverGreen) | Patching framework; Intel display fallback (WhateverGreen is transitional) |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) | SMC emulation and sensors |
| [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [VoodooPS2](https://github.com/acidanthera/VoodooPS2) | Touchpad and keyboard |
| [CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) | Hybrid CPU topology |
| [ECEnabler](https://github.com/1Revenger1/ECEnabler), [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) | Laptop EC and brightness-key support |
| [NVMeFix](https://github.com/acidanthera/NVMeFix), [RestrictEvents](https://github.com/acidanthera/RestrictEvents) | NVMe and system compatibility |
| [USBToolBox](https://github.com/USBToolBox/kext), [XHCI-unsupported](https://github.com/RehabMan/OS-X-USB-Inject-All) | USB support |
| [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X) | Ethernet driver |
| [AirportMtkWlan](https://github.com/Arxusion/AirportMtkWlan) | MediaTek MT7921 Wi-Fi, Tahoe build |
| [WhateverXe](https://github.com/b00t0x/WhateverXe) | Intel Xe-LP graphics: Lilu plugin that prepares the Apple drivers for Tiger Lake–Raptor Lake iGPUs. Upstream `0.7.0` is the base in `EFI/`; `0.8.0` loses the framebuffer allocation on `46A6` eDP ([#68](https://github.com/b00t0x/WhateverXe/issues/68)). |
| [WhateverXe Graphics](https://github.com/b00t0x/WhateverXe-Graphics) | Signed userspace half of WhateverXe (accelerator, framebuffer, Metal plugin/translator). Installs under `/Library` + AuxKC; `0.4.1` matches WEX `0.8.0`. Also the source of the **AMFIPass 1.4.1 Mod** we run. |
| [AMFIPass](https://github.com/dhinakg/AMFIPass) | AMFI compatibility. `master` carries upstream 1.4.1 for the NullMoth driver; this branch carries the b00t0x **Mod** build from WhateverXe-Graphics `extras/`, which WhateverXe requires instead of upstream. Never load both. |

## Graphics

| Project | How we use it |
|---|---|
| [NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) | NVIDIA RTX 3050 Mobile driver: NVRM/NVAccel/NVRMFB/NVRMAGDC in `/Library/Extensions`, Metal plugin in `/Library/GPUBundles`. Ampere laptop validation is still pending upstream. |
| [1401](https://github.com/nullmoth/1401) | Mac/Windows installer that owns the NVIDIA install and removal path. |
| [WTLIntelGfx](https://github.com/watchthelight-labs/WTLIntelGfx) (XeGfx, branch `main`, tag `v0.0.47`) | The target for Intel internal-panel acceleration: Linux i915 on XNU, Mesa ANV and a NullMoth-derived Metal accelerator. Uses the real `46A6`, no spoof, no WhateverGreen. Alder Lake is at the read-only probe: stage 2 passes on `46A6`; stage 4+ needs `adlp_guc_70.bin`, which upstream does not link. We add it (GuC v70.49.4 from linux-firmware, whose i915 blobs now live under `i915/`) plus the plugin/translator install; the macOS runbook and staged sources are on the utility drive. Installs into `/Library/Extensions` + AuxKC and `/Library/GPUBundles`, never the EFI. Licence is split: BSD-2-Clause shim/build/tools, PolyForm Noncommercial 1.0.0 for the plugin, accelerator, AGDC and the Intel framebuffer, LGPL-3.0 translator. |
| [WTLNvidiaGfx](https://github.com/watchthelight-labs/WTLNvidiaGfx) (default branch `nvgfx-2.6.2`; `main` mirrors upstream) | Reference only, not installed. NullMoth fork kept for an RTX 5070 Laptop (`10DE:2D18`); it adds nothing for our Ampere `10DE:25A2`, which upstream still lists as pending validation. Its `xe-2.6.2` branch holds the plugin/accelerator history that now lives in WTLIntelGfx. |
| [nickk19/WhateverXe](https://github.com/nickk19/WhateverXe) (branch `display13-edp-keep`, 0.7.0 base) | **Source of the kext we run.** Three commits over 0.7.0: admit the eDP boot port with native mode 0 at the firmware handoff ([#43](https://github.com/b00t0x/WhateverXe/issues/43)), treat VBT panel type `0xFF` as panel type 0, and the opt-in `-wex-edp-keep`. Also has a 0.8.0 branch (`display13-edp-keep-080`, `-wex-edp-blank`) we do not build. |
| [Thatisjigen/WhateverXe](https://github.com/Thatisjigen/WhateverXe) (branch `pr/edp-handoff-0.7.0`) | Same handoff admission on a 0.7.0 base plus a single-output CDCLK path when only the panel has a framebuffer. Built as a second candidate; the deployed kext is the nickk19 base. A copy of the three standard eDP blockers, tested on an MSI Katana, is written up in [#35](https://github.com/b00t0x/WhateverXe/issues/35) — we took its fixes 1 and 3 verbatim. |
| [sulthonuladib/WhateverXe](https://github.com/sulthonuladib/WhateverXe) (fork, branch `adlp-panel-route`) | Our build branch and CI: upstream `ci.yml` builds RELEASE on `macos-15-intel` from that branch and uploads artifacts (no release is created on a fork). Carries the two changes upstream does not: the lenient VBT parse behind `-wex-panel-fallback` (duplicate DDI, duplicate internal child) and `-wex-no-tc`, which drops the unused TC1..4 routes so `wrapDisplay13FramebufferStart()` stops refusing with `ADLPFBTCUnavailable`. Deployed binary `420fcb5a…`, CI run 42746818853. |

## Testing and verification

| Project | How we use it |
|---|---|
| [WTLGpuGuard](https://github.com/watchthelight-labs/WTLGpuGuard) | Boot-time safety net for GPU kext builds: confirm on screen or roll back and restart. ISC. |
| [WTLBootDump](https://github.com/watchthelight-labs/WTLBootDump) | Kernel log and IORegistry snapshots after boot, for boots that never reach the desktop. ISC. |
| [WTLHackintoshTest](https://github.com/watchthelight-labs/WTLHackintoshTest) | 119-probe feature test (Metal, display, audio, network, power) with evidence. ISC. |
| [WTLKcAbi](https://github.com/watchthelight-labs/WTLKcAbi) | Read-only link, symbol and vtable checks against the kernel collections; XeGfx uses it for its KPI checks. ISC. |

## Installer and audio

| Project | How we use it |
|---|---|
| [gibMacOS](https://github.com/corpnewt/gibMacOS), [UnPlugged](https://github.com/corpnewt/UnPlugged) | Installer download and offline package expansion |
| [AppleALC](https://github.com/acidanthera/AppleALC) | Audio reference only: Tahoe removed AppleHDA, so `alcid=` no longer works. |
| [WTLAudio](https://github.com/watchthelight-labs/WTLAudio) | The Tahoe analog-audio recipe: VoodooHDA 3.7.0 `LE` plus a small patch, matched to ALC257 behind `8086:7F50`. Our ALC245 sits behind the Alder Lake HDA controller, so it needs its own PCI match and pin-config layout; not a drop-in. BSD-2-Clause. |

## Studied, not used

| Project | Why not |
|---|---|
| [WTLHybridGfx](https://github.com/watchthelight-labs/WTLHybridGfx) | Legion-specific Optimus/mux work. This laptop has no MUX and different ACPI paths; useful only as background. |
| [research](https://github.com/watchthelight-labs/research) | Public boot logs. The relevant one is a second HP Victus 15-fa0xxx (`46A3`, i7-12650H) whose stage 4 panic in XeGfx 0.0.38 led to the 0.0.47 fix. |
| [kitsuneislife/nmx-intel](https://github.com/kitsuneislife/nmx-intel) | The earlier copy-the-NVIDIA-frame framebuffer; rejected for its per-frame CPU cost. XeGfx renders on the Intel GPU and only copies the finished frame for now. |

## Not applicable here

The watchthelight repos for other hardware, kept in mind but not used:

- `WTLMtkWireless`, `WTLWifiMenu`, `WTLMtkBluetooth`, `WTLLegionBtFix` — MediaTek MT7925 (`14C3:7925`). Ours is an MT7921 (`14C3:7961`, Bluetooth `13D3:3567`); those cards are explicitly unsupported there.
- `WTLI2CArrowLake` — Arrow Lake-HX/800-series I2C controllers (`8086:7F4x`). Our ELAN0788 touchpad already works through VoodooI2C on Alder Lake.
- `WTLLegionCpuPower`, `WTLLegionCbmrFix`, `WTLLegionOpenCore`, `WTLWifiGuard`, `WTLStagedReboot` — Legion 5 15IAX10 platform and workflow tools.

## Source handling

Reference sources live under `.references/` (git-ignored) and are read-only. `~/repo/nullmoth/`
is the user's checkout and must not be modified by agents; build copies belong on APFS.
Software belongs to its respective authors and retains its licences. The NullMoth driver is
PolyForm Noncommercial 1.0.0 (plus LGPL-3.0 translator and MIT NVK changes); preserve its
licence and notices.

The watchthelight-labs clones under `.references/` are read-only too. Their default branches are
not all `main`: `WTLNvidiaGfx` defaults to `nvgfx-2.6.2`, and the Intel work there lives on
`xe-2.6.2`. Their NullMoth-derived kexts (plugin, accelerator, AGDC, Intel framebuffer) stay
PolyForm Noncommercial 1.0.0.
