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
| Wi-Fi | `AirportMtkWlan` v1.5.1 Tahoe build enabled in the deployed EFI; not yet loaded or tested |
| NVIDIA driver | Reported working; does not drive the internal panel |
| Intel Metal acceleration | Not working; XPS adaptation planned |
| Audio / Bluetooth / sleep / brightness | Not verified |

## Current setup

- `EFI/`: the single EFI source; git history is the rollback. 25 kexts, 9 SSDTs, 3 ACPI patches, Intel framebuffer
  properties, `SetApfsTrimTimeout=0`, `ScanPolicy=0`, `AirportMtkWlan` 1.5.1 Tahoe build.
- Deploy with `tools/deploy-efi.sh` (copy `EFI/` to the `MACEFI` volume, splice the private identity back in, then
  `ocvalidate` + file checks). `--check` proves the ESP is `EFI/` plus the identity only; `--capture` refreshes the
  git-ignored `EFI/OC/identity.plist` from the ESP. The committed config keeps `REPLACEME…` placeholders.
- `MACEFI` (vfat volume labelled `MACEFI`, currently `nvme0n1p3`): Tahoe 26.7.1 installs and boots from this EFI. It
  writes `opencore-<date>.txt` and any `panic-*.txt` to the partition root (`Target=67`).
- Wi-Fi: `AirportMtkWlan` 1.5.1 Tahoe build (`14c3:7961`), `MinKernel 25.0.0`/`MaxKernel 25.99.99`, `SimpleMtkWlan`
  kept disabled. Source release sha256 `07ee8815…b02f9f`, kext binary sha256 `18a3c427…667f53`.
- Graphics: iGPU presented as Tiger Lake (`device-id 499A0000`, `AAPL,ig-platform-id 0000499A`) with
  `NootedGreen` 1.0.0 (`MinKernel 25.0.0`, built from the XPS reference), its boot-args and `csr-active-config 0x0A13`.
  The user-space half (Apple's TGL bundles, HookCase, patched Metal driver) is installed from macOS with
  `zsh install.sh` (`macUtility/make-graphics-work.sh --install`); until that runs, Tahoe stays on the software renderer.
  Our `46A6` is a 96 EU / 8 L3 part, so no `ngreen-eu`/`ngreen-l3` (those are for 80 EU chips).
- Recovery entries are hidden by `HideAuxiliary=true`; press **Space** in OpenCore to show them.
- Next: run the user-space install, then verify `xe-topo = 24584` and Metal in `system_profiler`. nullmoth's NVIDIA
  driver v2.6.3 lists
  macOS 26, but Ampere validation is still pending and it cannot drive the internal eDP panel.

Acceleration needs macOS-side drivers and user-space components as well as EFI changes.
Build on APFS with Command Line Tools, and prepare EFI plus macOS-driver rollback before installation.
Audio needs separate work: ALC245 is supported by AppleALC, but Tahoe removed AppleHDA.

Hardware evidence is in `scan/`. Local downloads, identities, candidates and backups are git-ignored.
See [references and attribution](REFERENCES.md) and [agent rules](AGENTS.md).
