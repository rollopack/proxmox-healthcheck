# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-10-19

### Fixed

- Parse ATA SMART raw values (temperature, power-on hours, reallocated sectors)
  correctly when smartctl appends extra text such as `(Min/Max ...)`.

### Changed

- The SATA wear warning now relies on authoritative sources (remaining-life
  attributes, then P/E cycle counters rated via the new
  `PH_THRESH_SSD_PE_CYCLES`) and only warns on a vendor wear indicator when it
  is corroborated by other signals, avoiding false positives on drives whose
  `Media_Wearout_Indicator` is not a remaining-life percentage.
- Report P/E cycles, grown bad blocks and an explicit remaining-life metric
  when the drive exposes them.

## [0.1.0] - 2026-10-19

### Added

- Auto-discovery of ZFS pools, backing disks, network bridges, VMs and LXC
  containers, with per-guest state.
- Modular single-file layout: check layer that only records results, separate
  report layer.
- Checks for host resources, failed systemd units, ZFS pool health, datasets,
  ARC, TRIM, dedup, I/O, disk SMART/wear, VM/CT overcommit and real usage,
  network bridges, sensors, backups and replication.
- Optional coloured terminal output, optional report file, `--quiet` summary.
- Exit codes: 0 OK, 1 WARNING/CRITICAL, 2 usage/setup error.
- Configuration file and `PH_*` environment overrides for all thresholds.
- Test harness with fake Proxmox/ZFS commands and no external dependencies.

[0.1.0]: https://github.com/rollopack/proxmox-healthcheck/releases/tag/v0.1.0
[0.1.1]: https://github.com/rollopack/proxmox-healthcheck/releases/tag/v0.1.1
