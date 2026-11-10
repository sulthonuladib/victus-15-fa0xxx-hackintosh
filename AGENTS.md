# Agent rules

- Target **Tahoe 26.7.1 / 25G241**. Read [README.md](README.md) for hardware/status and
  [REFERENCES.md](REFERENCES.md) when working with upstream components.
- Leave `OMARCHY_EFI` (`/boot`, `/dev/nvme0n1p1`) untouched. Never repartition, format or
  write the whole `/dev/nvme0n1`. Ask before each internal-disk media write, including MACEFI.
- USB writes: only `tools/make-1401-stick.sh`, with its serial, size, transport and OS-partition
  checks intact. `/dev/sda` is historical; re-identify it and use the private `.stick-serial`.
- `EFI/` is the single EFI source and git history is the rollback: commit instead of keeping copy trees. Deploy with
  `tools/deploy-efi.sh`; never hand-edit the ESP. Preserve the private machine identity: it lives only in the deployed
  `MACEFI/EFI/OC/config.plist` and the git-ignored `EFI/OC/identity.plist`. The committed `EFI/OC/config.plist` keeps
  scrubbed placeholders and never a real serial, MLB, ROM or UUID.
- Preserve the HP ACPI/input setup. Never set `disable-gpu` at `PciRoot(0x0)/Pci(0x2,0x0)`.
  The Tiger Lake `device-id`/`AAPL,ig-platform-id` spoof and WhateverGreen are a **transitional
  internal-panel fallback** in the NVIDIA-HDMI baseline; they are not acceleration. Do not remove the
  fallback from `master` until XeGfx is proven. The XeGfx test config uses the real `46A6`, no spoof,
  no WhateverGreen, and `IONDRVSupport` present.
- NVIDIA: the NullMoth 1401 app owns the driver. Keep `NVRM`, `NVAccel`, `NVRMFB`, `NVRMAGDC`
  in `/Library/Extensions` and the AuxKC — never inject them from `EFI/`. Keep the HDMI path
  working. With WhateverGreen present, keep `gfxrst=4`. Keep `IONDRVSupport` excluded for the
  NVIDIA baseline. Use the 1401 picker entries for removal/one-time safe start; do not hand-edit
  the NVIDIA install.
- XeGfx (`WTLIntelGfx`, branch `main`, v0.0.47+) is the Intel acceleration path. Build and test it on
  macOS/APFS in a separate branch/config (`nmintelfb` already has the right EFI shape), with the
  working NVIDIA EFI kept as rollback. It installs into `/Library/Extensions` + AuxKC, never the EFI.
  It needs the real `46A6`, `IONDRVSupport` present, no WhateverGreen, and no spoof. Alder Lake is
  probe-only until `adlp_guc_70.bin` is linked: stop at `debug.xegfx_stage=3` and send reports to
  WTLIntelGfx #3. Do not make it the default, or drop `master`'s fallback, until the panel is proven.
  The ESP may carry the `nmintelfb` test config (it does since 2026-11-04) while `master` keeps the
  fallback; deploy and `--check` from whichever tree you want on the ESP.
  The macOS build/install tooling and the staged sources live on the utility drive in
  `scripts/xegfx/` (`RUNBOOK.md`, `xegfx-run.sh`); use them instead of improvising. The
  `adlp_guc_70.bin` patch (`xegfx-patch-guc.sh`, GuC v70.49.4) and our plugin/translator install
  step are required on this machine; upstream v0.0.47 omits both.
- When source references are needed, use the repos in `REFERENCES.md`. Reuse an existing checkout under `.references/`
  (including symlinks); if missing, clone only the needed repo into `.references/<repo>/`. Keep reference sources
  read-only and git-ignored. watchthelight-labs default branches vary: `WTLNvidiaGfx` is `nvgfx-2.6.2`, not `main`.
  Their MT7925 kexts do not support our MT7921 (`14C3:7961`). `~/repo/nullmoth/` is user-maintained: when asked, fetch tags and check out the latest
  release tag, but do not edit its source or working tree. Keep local changes in patches/stashes/branches; preserve
  upstream licences/notices. Build copies belong on APFS, not the repo. Keep the source tag matched to the installed
  1401/driver version before building from the NullMoth tree.
- Privileged steps run with `sudo -S` (password on stdin) or `osascript … with administrator
  privileges` only when a terminal is not available; never open a GUI dialog from an agent pane.
  The machine password itself is given out-of-band and must never appear in a committed file, a
  script under `tools/`, or a report on the utility drive.
- When spawning work in a rex pane, start the interactive `pi "<prompt>"`, not `pi -p`: print mode
  buffers everything until it exits and leaves the pane blank, so nobody can watch progress or
  interrupt it. Collect results with `rex capture` and the report file the agent writes.
- Validate EFI edits with matching-version `ocvalidate` plus referenced-file/dependency checks. The
  binary is host-specific: `.downloads/ocvalidate-macos/` (1.0.8, from the OpenCore RELEASE zip) and
  `.downloads/ocvalidate-linux/`; `tools/deploy-efi.sh` picks by `uname -s` and refuses to write a
  non-FAT32 or system volume. Use `python3 -B` for upstream imports; review recommendations instead
  of blindly applying them.
- Two findings are settled and should not be re-litigated without new evidence: (1) **Metal 3** — the
  family flag is a 2-byte patch at `AppleIntelTGLGraphicsMTLDriver` offset `0x22957`
  (`0x2711`→`0x2712`), but real Metal 3 dies in our own `XeCompilerAdapter` (mesh serialized
  request) and in the plugin's missing target architecture; keep the flag off, restore with
  `macUtility/whateverxe/mtl3-backup/restore-stock.sh`. (2) **dGPU off** — only PERST#/rail removal
  makes a PCI function disappear (`_STA = 0` does not, macOS scans the bridge); the firmware
  `POFF()` aborts on its first EC write when called from `_INI`, so `SSDT-DGPU-POFF2` replays just
  its MMIO tail via `\PIN`/`\_SB.SGOV` with GNVS pin numbers.
- Report measured results separately from assumptions. `EXITBS:START` only means handover; GUI/Metal success needs a
  real boot test. Keep README status current and concise.
- Keep docs to these three files. Use release tags/commit IDs and relevant source links; avoid session handoffs,
  duplicated research logs and per-source checksum manifests.
