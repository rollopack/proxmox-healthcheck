# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.4] - 2026-10-21

### Fixed

- Recognize Proxmox all-guest backup jobs (`all: 1` / `--all 1`) so a complete
  successful task can stop the history scan without explicit positional VMIDs.

## [0.1.3] - 2026-10-21

### Fixed

- Attribute backup tasks to their VMs/CTs by reading the task log, so scheduled
  `vzdump` tasks without a guest id are no longer reported as a false warning.
- Report per-guest backup freshness and failures from the log, including
  multi-guest tasks and failed tasks that completed only some guests.
- Fall back to the node-level freshness of the latest successful `vzdump` task
  when task logs cannot be read, instead of emitting a misleading warning.
- Keep long guest lists and UPIDs distinct in the task report.

### Performance

- Stop scanning older task logs once a successful task covers all explicitly
  selected guests, avoiding redundant log requests.

### Added

- `PH_BACKUP_TASK_HISTORY` (default 30) controls how many recent `vzdump` tasks
  are inspected.

## [0.1.2] - 2026-10-21

### Fixed

- Load the file passed to `--config` and fail clearly when that explicit path
  is unreadable.
- Parse formatted JSON with whitespace and multiline objects, including braces
  inside quoted strings; report unavailable VM usage data instead of claiming
  that sampling succeeded.
- Check backup freshness per VM/CT using the latest successful task and warn
  for stale or missing successes; an older failed task no longer overrides a
  newer success.

### Added

- Optional host-wide SMART discovery with `PH_SMART_SCAN_ALL_DISKS=1` to include
  `lsblk` disk devices outside ZFS pools.

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
[0.1.2]: https://github.com/rollopack/proxmox-healthcheck/releases/tag/v0.1.2
