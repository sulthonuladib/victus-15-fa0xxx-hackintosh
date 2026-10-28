# HP Victus 15-fa0xxx — macOS Tahoe

Target: **macOS Tahoe 26.7.1 (25G241)** with OpenCore.
Goal: internal-panel Intel graphics acceleration using the XPS/NootedGreen reference.

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

## What works

These are prior user reports on this laptop. **Tahoe boot and runtime behavior are not yet verified.**

| Feature | Status |
|---|---|
| Internal display | Working with Tiger Lake spoof; no Intel graphics acceleration |
| Keyboard / touchpad | Working with VoodooPS2 / VoodooI2C |
| Wi-Fi | Previously working; disabled in the Tahoe candidate pending an OS-matching driver |
| NVIDIA driver | Reported working; does not drive the internal panel |
| Intel Metal acceleration | Not working; XPS adaptation planned |
| Audio / Bluetooth / sleep / brightness | Not verified |

## Current setup

- `EFI/`: original source configuration with the known display/input setup; public identity placeholders.
- `out/tahoe-baseline/EFI/`: private Tahoe candidate: 25 kexts, 9 SSDTs, 3 ACPI patches, Intel framebuffer
  properties, `SetApfsTrimTimeout=0`, `ScanPolicy=0`.
- `MACEFI` (`nvme0n1p4`): the candidate is deployed here as of 2026-10-28 (deployed and validated offline, boot
  not tested). The previous EFI is backed up in `out/backups/macefi-EFI-20261028-123735/`. With
  `Misc > Debug > Target=67` each boot writes `opencore-<date>.txt` and any `panic-*.txt` to this partition's root.
- Recovery entries are hidden by `HideAuxiliary=true`; press **Space** in OpenCore to show them.
- Next: boot the deployed candidate, read the log it leaves on `MACEFI`, confirm recovery display/input, then adapt
  and test the graphics stack.

Acceleration needs macOS-side drivers and user-space components as well as EFI changes.
Build on APFS with Command Line Tools, and prepare EFI plus macOS-driver rollback before installation.
Audio needs separate work: ALC245 is supported by AppleALC, but Tahoe removed AppleHDA.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are git-ignored.
See [references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
