# Agent rules

- Target **Tahoe 26.7.1 / 25G241**. Read [README.md](README.md) for hardware/status and
  [REFERENCES.md](REFERENCES.md) when working with upstream components.
- Leave `OMARCHY_EFI` (`/boot`, `/dev/nvme0n1p1`) untouched. Never repartition, format or
  write the whole `/dev/nvme0n1`. Ask before each internal-disk media write, including MACEFI.
- USB writes: only `tools/make-1401-stick.sh`, with its serial, size, transport and OS-partition
  checks intact. `/dev/sda` is historical; re-identify it and use the private `.stick-serial`.
- `EFI/` is the single EFI source and git history is the rollback: commit instead of keeping copy trees. Deploy
  `EFI/` to `MACEFI`; do not create `out/`-style backups or `.bak-*` copies. Preserve the private machine identity:
  it stays only in the deployed `MACEFI/EFI/OC/config.plist`; the committed `EFI/OC/config.plist` keeps scrubbed
  placeholders and never a real serial, MLB, ROM or UUID.
- Preserve the HP ACPI/input setup and Intel display properties: no `disable-gpu` at
  `PciRoot(0x0)/Pci(0x2,0x0)`; retain `device-id=499A0000`, `AAPL,ig-platform-id=0000499A`
  and framebuffer properties. Keep `boot-args` in NVRAM Delete as well as Add; TRIM timeout is 0.
- Keep NVIDIA injection out of the installer: prior NVRMFB/NVAccel/NVRMAGDC injection failed.
  Review graphics drivers as a complete stack; prepare EFI and macOS-driver rollback together.
- When source references are needed, use the repos in `REFERENCES.md`. Reuse an existing
  checkout under `.references/` (including symlinks); if missing, clone only the needed repo
  into `.references/<repo>/`. Keep reference sources read-only after cloning and git-ignored.
  Never modify `~/repo/nullmoth/`; preserve upstream licences/notices.
  Adapt the XPS graphics stack to our hardware; retain our complete HP EFI and identity.
- Validate EFI edits with matching-version `ocvalidate` plus referenced-file/dependency checks.
  1401's `validate` CLI is absent here; its Python API is available. Use `python3 -B` for
  upstream imports; review efidoctor recommendations instead of blindly applying NVIDIA fixes.
- Report measured results separately from assumptions. `EXITBS:START` only means handover;
  GUI/Metal success needs a real boot test. Keep README status current and concise.
- Keep docs to these three files. Use release tags/commit IDs and relevant source links;
  avoid session handoffs, duplicated research logs and per-source checksum manifests.
