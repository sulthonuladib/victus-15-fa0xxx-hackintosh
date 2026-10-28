# References and attribution

## Components used by this EFI

| Project | Contribution |
|---|---|
| [OpenCore](https://github.com/acidanthera/OpenCorePkg) | Bootloader |
| [Lilu](https://github.com/acidanthera/Lilu), [WhateverGreen](https://github.com/acidanthera/WhateverGreen) | Patching framework and graphics properties |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) | SMC emulation and sensors |
| [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [VoodooPS2](https://github.com/acidanthera/VoodooPS2) | Touchpad and keyboard |
| [CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) | Hybrid CPU topology |
| [ECEnabler](https://github.com/1Revenger1/ECEnabler), [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) | Laptop EC and brightness-key support |
| [NVMeFix](https://github.com/acidanthera/NVMeFix), [RestrictEvents](https://github.com/acidanthera/RestrictEvents) | NVMe and system compatibility |
| [USBToolBox](https://github.com/USBToolBox/kext), [XHCI-unsupported](https://github.com/RehabMan/OS-X-USB-Inject-All) | USB support |
| [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X) | Ethernet driver |
| [SimpleMtkWlan](https://github.com/flxxxxddd/SimpleMtkWlan) | Existing MediaTek Wi-Fi kexts; disabled in the Tahoe candidate |

## Acceleration and installer references

| Project | How we use it |
|---|---|
| [XPS Iris Xe Tahoe](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe) | Main acceleration reference: modified NootedGreen, HookCase, TGL drivers and Metal/compiler adaptations. Not installed on this Victus yet. |
| [NootedGreen](https://github.com/sgiammori/NootedGreen) | Original project underlying the XPS graphics work |
| [WhateverXe](https://github.com/b00t0x/WhateverXe), [Graphics package](https://github.com/b00t0x/WhateverXe-Graphics) | Alternative Intel reference. WEX 0.5.0 still requires implementation for Alder Lake-H/P/U. |
| [NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) | User-tested NVIDIA path. Its separate Intel NMXGPU test program is [on hold](https://github.com/nullmoth/nvidia-macos-driver/issues/243). |
| [1401](https://github.com/nullmoth/1401), [OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify) | Original EFI generation and hardware/validation tooling |
| [gibMacOS](https://github.com/corpnewt/gibMacOS), [UnPlugged](https://github.com/corpnewt/UnPlugged) | Installer download and offline package expansion |
| [AppleALC](https://github.com/acidanthera/AppleALC) | Audio reference; not installed. Tahoe requires additional work for AppleHDA-based analog audio. |

The XPS [46A6/internal-panel report](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/issues/16)
is encouraging, but it is a different laptop. Adapt graphics work while retaining our HP ACPI/input setup.

Software belongs to its respective authors and retains its licences.
The XPS/NootedGreen work uses the Thou Shalt Not Profit licence; preserve its licence and notices.
