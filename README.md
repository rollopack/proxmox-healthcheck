# proxmox-healthcheck

`proxmox-healthcheck` is a self-contained Bash script that runs diagnostics and
integrity checks on a Proxmox VE node or cluster, its ZFS storage and its VMs
and LXC containers. It is designed to be **portable**: nothing is hardcoded, and
any feature that is not present on the machine is skipped instead of causing an
error.

- Single file, no installation required, no external runtime dependencies.
- Auto-discovery of ZFS pools, disks, network bridges, VMs and containers.
- Readable, optionally coloured text output, and an optional report file.
- Standard exit codes suitable for manual runs and simple automation.

## Features

- **Auto-discovery** – detects the pools from `zpool list -H -o name`, the
  backing disks, the network bridges and every VM/CT with its state. No pool,
  disk or guest name is hardcoded.
- **Modular internals** – the checks only *record* results; a separate report
  layer prints them. Adding a check does not touch the output code.
- **Graceful degradation** – missing `zpool`, `zfs`, `qm`, `pct`, `pvesh`,
  `smartctl`, `sensors`, `ipmitool`, `iostat`, `pvesr` etc. make the related
  check *skip*, never fail.
- **No exotic dependencies** – numeric math and byte formatting are done with
  `awk`, so `bc` and `numfmt` are not required.
- **Colour on demand** – colours are enabled only on a TTY and can be disabled
  with `--no-color` (the `NO_COLOR` convention is honoured too).

## Requirements

- Proxmox VE 7 or 8 (Debian based) with `bash` 4.4+.
- ZFS, Proxmox tooling, `smartctl`, `sensors`, `ipmitool`, `sysstat` and
  `pvesr` are all optional: the corresponding checks are skipped when absent.
- `root` is only needed for the parts that require it (SMART data, IPMI, some
  ZFS/systemd queries). Without root those checks degrade to informational
  notes.

## Installation

`proxmox-healthcheck` is a single, self-contained script.

### Quick install (download)

Download the script and make it executable (`wget` is available by default on
Proxmox VE):

```sh
wget -O /usr/local/bin/proxmox-healthcheck \
  https://raw.githubusercontent.com/rollopack/proxmox-healthcheck/main/proxmox-healthcheck
chmod 0755 /usr/local/bin/proxmox-healthcheck
```

Optional configuration file:

```sh
wget -O /etc/proxmox-healthcheck.conf \
  https://raw.githubusercontent.com/rollopack/proxmox-healthcheck/main/proxmox-healthcheck.conf.example
```

### From a local copy

Copy the script anywhere and make it executable:

```sh
install -m 0755 proxmox-healthcheck /usr/local/bin/proxmox-healthcheck
```

Optional configuration file:

```sh
install -m 0644 proxmox-healthcheck.conf.example /etc/proxmox-healthcheck.conf
```

To update, simply replace the file with the desired version.

## Usage

```sh
proxmox-healthcheck [options]
```

| Option | Description |
| --- | --- |
| `-c, --check ID[,ID...]` | run only the given checks (see `--list-checks`) |
| `--pool NAME[,NAME]` | restrict ZFS checks to these pools |
| `--node NAME` | Proxmox node name (default: auto-detected) |
| `-o, --output FILE` | also write the report to `FILE` |
| `--no-color` | disable coloured output |
| `-q, --quiet` | print only the final summary |
| `--config FILE` | configuration file (default: `/etc/proxmox-healthcheck.conf`) |
| `--list-checks` | list the available check ids and exit |
| `-v, --version` | print the version and exit |
| `-h, --help` | show the help and exit |

Examples:

```sh
# Full report on screen.
proxmox-healthcheck

# Only ZFS pool health and disk wear, for a specific pool.
proxmox-healthcheck -c zfs.pool_health,storage.smart --pool rpool

# Save a plain-text report and keep the terminal clean.
proxmox-healthcheck --no-color -o /var/tmp/pve-report.txt -q
```

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | everything is OK |
| `1` | at least one check reported WARNING or CRITICAL |
| `2` | usage or setup error (unknown option/check, unwritable output file) |

### Output

The report is human readable and structured into one section per check, each
ending with a `Result:` line. A final summary lists the status of every check
and repeats the findings that need attention. With `-o FILE` the same text is
written to `FILE` without colour codes.

## Checks

Run `proxmox-healthcheck --list-checks` for the current list. See
[docs/checks.md](docs/checks.md) for the metrics and thresholds of each check.

| Check id | What it inspects |
| --- | --- |
| `host.resources` | CPU cores, load, RAM, swap usage, `iostat -x` |
| `host.systemd` | failed systemd units |
| `zfs.pool_health` | pool state, capacity, fragmentation, last scrub, data errors |
| `zfs.datasets` | datasets and zvols, thin provisioning |
| `zfs.arc` | ARC size, min/max and hit ratio |
| `zfs.trim` | `autotrim`, periodic TRIM (systemd timers, Debian cron) |
| `zfs.dedup` | dedup property and ratio |
| `zfs.iostat` | live `zpool iostat -v` sampling |
| `storage.smart` | SMART wear, reallocated sectors, temperature |
| `vm.overcommit` | allocated vCPU/RAM vs physical resources |
| `vm.usage` | real CPU/RAM usage of running guests via `pvesh` |
| `net.bridges` | bridge state, addresses, member interfaces |
| `hardware.sensors` | `lm-sensors` and IPMI temperatures/fans |
| `backup.status` | recent `vzdump` tasks (only if backups are configured) |
| `replication.status` | `pvesr status` (only if replication is configured) |

## Configuration

Settings can be provided, from lowest to highest priority, by:

1. built-in defaults,
2. the configuration file (`/etc/proxmox-healthcheck.conf`),
3. environment variables (`PH_*`),
4. command-line options.

See `proxmox-healthcheck.conf.example` for the full list, including every
threshold (pool capacity, fragmentation, scrub age, overcommit, SSD wear,
temperature, backup age, swap usage, ...).

## Testing

The tests use fake `zpool`, `zfs`, `qm`, `pct`, `pvesh`, `smartctl`, `ip`,
`lsblk` and friends, and need no Proxmox node:

```sh
tests/run.sh
```

The script is also expected to be clean under
[ShellCheck](https://www.shellcheck.net/) (`shellcheck proxmox-healthcheck`).

## Contributing

Issues and pull requests are welcome. Please keep the script dependency-free,
add or update a test in `tests/run.sh` for behavioural changes, and make sure
`shellcheck proxmox-healthcheck` stays clean.

## License

MIT. See [LICENSE](LICENSE).
