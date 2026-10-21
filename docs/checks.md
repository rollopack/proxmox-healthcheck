# Checks reference

This document describes every check: what it inspects, the metrics it reports
and the conditions that produce a WARNING or CRITICAL result. All thresholds
are configurable (see `proxmox-healthcheck.conf.example`).

Checks are run per pool or per guest where relevant, and are **skipped** (never
failed) when the required tool, file or object is not available.

## host.resources

- **CPU cores (online)** – from `nproc`.
- **Load / uptime** – from `uptime`.
- **Memory** – used/total from `free -h`.
- **Swap used** – WARNING when swap usage reaches `PH_THRESH_SWAP_WARN_PCT`%
  of the total swap; informational when below.
- **I/O statistics** – `iostat -x` for `PH_IO_SAMPLES` samples (skipped if
  `sysstat` is not installed).

## host.systemd

Lists failed systemd units (`systemctl --failed`). WARNING when at least one
unit is failed. Skipped if `systemctl` is unavailable.

## zfs.pool_health

For every discovered pool:

- **Health** – CRITICAL when the pool is not `ONLINE`.
- **Capacity used** – WARNING at `PH_THRESH_POOL_CAP_WARN`%, CRITICAL at
  `PH_THRESH_POOL_CAP_CRIT`%.
- **Fragmentation** – WARNING at `PH_THRESH_POOL_FRAG_WARN`%. A `-` value is
  reported as-is and never triggers an error.
- **Last scan** – WARNING when older than `PH_THRESH_SCRUB_WARN_DAYS`,
  CRITICAL beyond `PH_THRESH_SCRUB_CRIT_DAYS`. A running scrub is
  informational, a running resilver is a WARNING, `none requested` is a
  WARNING.
- **Data errors** – CRITICAL for any `errors:` other than
  `No known data errors`.

## zfs.datasets

Lists datasets and zvols (largest first) and shows thin-provisioning details
(`volsize` vs `used`) for zvols. Informational.

## zfs.arc

Reports current/min/max ARC size and the hit ratio, read from
`/proc/spl/kstat/zfs/arcstats` (overridable via `PH_ARCSTATS`) with an
`arc_summary` fallback. The hit ratio only produces a WARNING when
`PH_THRESH_ARC_HIT_WARN` is greater than 0.

## zfs.trim

- **autotrim** property of the pool.
- Periodic TRIM: systemd timers `zfs-trim-weekly@<pool>.timer` /
  `zfs-trim-monthly@<pool>.timer`, and the Debian cron
  (`/etc/cron.d/zfsutils-linux` with `org.debian:periodic-trim`).
- WARNING when neither `autotrim=on` nor an explicit periodic TRIM is active.

## zfs.dedup

Reports the `dedup` property and `dedupratio`. WARNING (informational value)
when dedup is enabled because of its memory cost.

## zfs.iostat

Runs `zpool iostat -v <pool>` for `PH_IO_SAMPLES` samples. Informational.

## storage.smart

For every unique disk backing the selected pools:

- Metrics: power-on hours, temperature, NVMe percentage used, available spare,
  reallocated sectors, plus whichever wear sources the drive exposes:
  - remaining-life attribute (`Percent_Lifetime_Remain`,
    `Percentage_Lifetime_Remain`, `SSD_Life_Left`);
  - P/E cycle counters (`Maximum_PE_Cycles*`, `Average_PE_Cycles*`);
  - the vendor wear indicator (`Media_Wearout_Indicator`,
    `Wear_Leveling_Count`).
- By default, SMART checks cover disks backing the selected ZFS pools. Set
  `PH_SMART_SCAN_ALL_DISKS=1` to add all devices reported by `lsblk` as physical
  disks, including disks outside ZFS pools.
- WARNING sources, in order of precedence:
  1. NVMe percentage used at `PH_THRESH_SSD_WEAR_WARN`%;
  2. remaining-life attribute below `100 - PH_THRESH_SSD_WEAR_WARN`%;
  3. P/E counters at `PH_THRESH_SSD_WEAR_WARN`% of `PH_THRESH_SSD_PE_CYCLES`
     (only when that rating is set, `> 0`);
  4. vendor wear indicator below `100 - PH_THRESH_SSD_WEAR_WARN`%, but only
     when no authoritative source above is available **and** it is corroborated
     by another signal (reallocated sectors `> 0`, grown bad blocks `> 0`, or
     available spare `< 100`).
- The vendor wear indicator alone is informative only: its meaning differs
  between vendors (some report remaining life, others a firmware-specific
  packed value), so an uncorroborated low reading does not raise a WARNING.
- Other warnings: reallocated sectors above `PH_THRESH_REALLOC_WARN`,
  temperature at `PH_THRESH_TEMP_WARN`.
- CRITICAL: temperature at `PH_THRESH_TEMP_CRIT`.
- Skipped when `smartctl` is missing; individual devices with no readable data
  are reported as informational notes.

## vm.overcommit

Compares allocated vCPU/RAM (from `qm config` / `pct config`) with the physical
resources. WARNING when the vCPU ratio exceeds
`PH_THRESH_VCPU_OVERCOMMIT_WARN` or the RAM ratio exceeds
`PH_THRESH_RAM_OVERCOMMIT_WARN`.

## vm.usage

Real CPU and memory usage of running guests via
`pvesh get /nodes/<node>/<type>/<id>/status/current`. `%CPU` is a fraction of
one host core. WARNING when usage data cannot be retrieved for one or more
running guests; skipped if `pvesh` is not available.

## net.bridges

Discovers bridges from `ip link show type bridge` and
`PH_NET_INTERFACES`, then reports state, addresses and member interfaces.
WARNING when a bridge is not `UP` or its state is unknown. Skipped when there
is no bridge.

## hardware.sensors

Dumps `sensors` output and the IPMI `temp/fan/cpu/mb` sensors when the tools
are installed. Informational.

## backup.status

Only runs when a backup job is configured (`/cluster/backup` or
`/etc/pve/vzdump.cron`). Lists recent `vzdump` tasks and reconstructs the
guests of each task from its log (`pvenode task log`, with the
`/nodes/{node}/tasks/{upid}/log` API as fallback), because scheduled
multi-guest tasks usually carry no guest id. The log is parsed for
`Starting Backup of VM/CT <id>`, `VM Name:` and `Finished Backup of VM/CT <id>`,
so `qemu` and `lxc` guests are handled alike and a single task can report
several guests.

A guest is considered successfully backed up by a task when the task status is
`OK`, or when a failed task contains its `Finished Backup of VM/CT` line. The
check warns when a guest has no successful task in the inspected history, when
its latest successful backup is at least `PH_THRESH_BACKUP_AGE_DAYS` days old,
or when the most recent task that included it did not finish `OK`. It inspects
the most recent `PH_BACKUP_TASK_HISTORY` tasks (default 30).
When exactly one configured job lists its guests in the task-log command line,
the scan stops once every selected guest has a known successful backup; older
logs cannot change freshness or the latest-task result.

If no task log can be read, the guest id is taken from the task `id` field when
Proxmox provides one; otherwise the check falls back to the freshness of the
latest successful `vzdump` task for the node and reports that per-guest
attribution is unavailable. The backup `note` field is not used. Skipped if
`pvesh` is missing or no backup job exists.

## replication.status

Prints `pvesr status` and warns on replication failures. Skipped when `pvesr`
is unavailable or no replication job is configured.
