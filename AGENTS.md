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
- When source references are needed, use the repos in `REFERENCES.md`. Reuse an existing checkout under `.references/`
  (including symlinks); if missing, clone only the needed repo into `.references/<repo>/`. Keep reference sources
  read-only and git-ignored. watchthelight-labs default branches vary: `WTLNvidiaGfx` is `nvgfx-2.6.2`, not `main`.
  Their MT7925 kexts do not support our MT7921 (`14C3:7961`). `~/repo/nullmoth/` is user-maintained: when asked, fetch tags and check out the latest
  release tag, but do not edit its source or working tree. Keep local changes in patches/stashes/branches; preserve
  upstream licences/notices. Build copies belong on APFS, not the repo. Keep the source tag matched to the installed
  1401/driver version before building from the NullMoth tree.
- Validate EFI edits with matching-version `ocvalidate` plus referenced-file/dependency checks. Use `python3 -B` for
  upstream imports; review recommendations instead of blindly applying them.
- Report measured results separately from assumptions. `EXITBS:START` only means handover; GUI/Metal success needs a
  real boot test. Keep README status current and concise.
- Keep docs to these three files. Use release tags/commit IDs and relevant source links; avoid session handoffs,
  duplicated research logs and per-source checksum manifests.
