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
| [SimpleMtkWlan](https://github.com/flxxxxddd/SimpleMtkWlan) | Older MediaTek Wi-Fi kexts; disabled |
| [AMFIPass](https://github.com/dhinakg/AMFIPass) | AMFI compatibility for the NullMoth driver (1401 copy, 1.4.1) |

## Graphics

| Project | How we use it |
|---|---|
| [NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) | NVIDIA RTX 3050 Mobile driver: NVRM/NVAccel/NVRMFB/NVRMAGDC in `/Library/Extensions`, Metal plugin in `/Library/GPUBundles`. Ampere laptop validation pending upstream. |
| [1401](https://github.com/nullmoth/1401) | Mac/Windows installer used for the NVIDIA driver and the OpenCore changes. It owns the NVIDIA install/remove path. |
| NullMoth `kexts/NMIntelFB` | Experimental Intel-panel framebuffer from the same driver repository. Test build only; not installed by the 1401 package. Uses the real Intel display engine and the NVIDIA copy path (head 4). |

## Installer and audio

| Project | How we use it |
|---|---|
| [gibMacOS](https://github.com/corpnewt/gibMacOS), [UnPlugged](https://github.com/corpnewt/UnPlugged) | Installer download and offline package expansion |
| [AppleALC](https://github.com/acidanthera/AppleALC) | Audio reference; not installed. Tahoe requires additional work for AppleHDA-based analog audio. |

## Source handling

Reference sources live under `.references/` (git-ignored) and are read-only. `~/repo/nullmoth/`
is the user's checkout and must not be modified by agents; build copies belong on APFS.
Software belongs to its respective authors and retains its licences. The NullMoth driver is
PolyForm Noncommercial 1.0.0 (plus LGPL-3.0 translator and MIT NVK changes); preserve its
licence and notices.
